#
# lib/usbmon/digitdia.rb
#
# 'Interpreter' for usbmon dumps talking to a 'DigitDia' slide scanner
#
# UsbMon::Event
#     attr_reader :urb, :timestamp, :utd, :bus, :device, :endpoint, :status, :dlen, :dtag, :data
#

module UsbMon
  class DigitDia
    def initialize debug_level = 0
      @debug_level = debug_level
      @state = :idle
      @counts = {}
      @ieee1284_cmd_index = 0
      # cmd at index 7
      @ieee1284_cmd_sequence = [0xff, 0xaa, 0x55, 0x00, 0xff, 0x87, 0x78, 0x00, 0xff]
      @scsi_cmd_index = 0
      @scsi_cmd_data = []
      @scsi_extra_count = 0
      @scsi_extra_data = []
    end
    
    #
    # type: :usb (lowest level)
    #       :ctrl (ieee1284)
    #       :cmd (scsi cmd prep)
    #       :scsi
    #       :top
    #
    DEBUG_LEVELS = [ :none, :top, :scsi, :cmd, :ctrl, :usb ]
    def message type, msg, event
      level = DEBUG_LEVELS.find_index type
      raise "Unknown debug level #{type.inspect}" unless level
#      puts "Message type #{type.inspect} (level #{level}), debug_level #{@debug_level}"
      return if level > (@debug_level % 10)
      time = (event.timestamp - @start) / 1000
      if @previous
        delta = time - @previous
      else
        delta = 0
      end
      puts "(+%5d ms) t+%5d: #{type} - %s" % [delta.to_i, time.to_i, msg]
      puts "\t\t#{event.raw}" if @debug_level > 10
      @previous = time
    end
    #
    # statistics
    #
    def increment what, data
      @counts[what] ||= []
      @counts[what] << data
    end

    def get_value data
      low = data.shift.hex
      low + data.shift.hex*256
    end

    def explain_filter val
      case val
      when 1
        "filter neutral"
      when 2
        "filter red"
      when 4
        "filter green"
      when 8
        "filter blue"
      else
        "filter #{val}"
      end
    end
    #
    # explain 'write' sub-commands
    # see "command codes used in the data part of a SCSI write command" at end of backed/pie-scsidef.h
    #    
    def explain_write data, event
      cmd = get_value data
      len = get_value data
      if data.size < len # consistency check
        raise "Bad len (#{len}), only have #{data.size} bytes for #{data.inspect}"
      end
      case cmd
      when 0x12
        msg = "set_scan_frame"
      when 0x13
        fil = explain_filter(get_value data)
        val = get_value data
        msg = "set_exp_time #{fil}:#{val}%"
      when 0x14
        fil = explain_filter(get_value data)
        val = get_value data
        msg = "set_highlight_shadow #{fil}:#{val}%"
      when 0x95
        msg = "read_cal_info"
      else
        msg = "???<0x%02x>" % cmd
      end
      while !data.empty?
        val = get_value data
        msg << (" (%d/0x%04x)" % [val,val])
#        cmd << " #{val.inspect}"
      end
      message :scsi, "\t#{msg} #{data.inspect}", event
    end

    #################################
    # Error
    #
    
    #
    # interprete Error event
    #
    def interprete_error event
      raise "Unhandled! #{event.raw}"
    end
    
    #################################
    # Submission
    #
    def interprete_submission_bulk_input event
      # puts event
      # prep data read via callback bulk input
    end

    def interprete_submission_bulk_output event
      puts event
    end

    #
    # Setup 'Ci'
    #
    def interprete_submission_control_input event
      unless @state == :idle
        raise "Bad state #{@state}"
      end
      @state = :await_callback
      message :usb, ("\tGet status %04x,%04x" % [event.wValue,event.wIndex]), event
    end
    
    #
    # Setup 'Co'
    #
    def interprete_submission_control_output event
      unless @state == :idle
        raise "Bad state #{@state}"
      end
      if event.status == "s" # setup
        @state = event.utd
	case event.bmRequestType
	when 0x00 # Init
	  message :usb, "usb init bmRequestType 0x00", event
	when 0x02 # Init
	  message :usb, "usb 02 bmRequestType 0x02", event
	when 0x23 # 
	  message :usb, "usb 23 bmRequestType 0x23", event
	when 0x40 # Vendor -> Device
          unless event.wValue == 0x0082
            unless event.wLength == 1
              raise "Unusual S Co length #{event.wLength}: #{event.raw}"
            end
          end
          case [event.bRequest, event.wValue]
          when [0x04, 0x0082]
            unless event.wLength == 8
              raise "Unusual S Co length 0x82 #{event.wLength}: #{event.raw}"
            end
            # 8 bytes
            # repeat scsi length ?
            increment "4:82", event.data
          when [0x0c, 0x0085]
            if @scsi_extra_count > 0
              @scsi_extra_data << event.data
              @scsi_extra_count -= 1
              if @scsi_extra_count == 0
                case @scsi_cmd_current
                when "d1"
                  if @scsi_extra_data[0] == '04'
                    direction = "next"
                  elsif @scsi_extra_data[0] == '05'
                    direction = "prev"
                  elsif @scsi_extra_data[0] == '40'
                    direction = "new box"
                  else
                    direction = "<UNKNOWN:#{@scsi_extra_data[0]}>" 
                  end
                  message :scsi, ("\t #{direction} - 0x%02x:%s" % [@scsi_extra_data.size, @scsi_extra_data.inspect]), event
                when "0a"
                  explain_write @scsi_extra_data, event
                when "15", "dc"
                  message :scsi, ("\t - data - 0x%02x:%s" % [@scsi_extra_data.size, @scsi_extra_data.inspect]), event
                when "10"
                  message :scsi, "mark : #{@scsi_extra_data.inspect}", event
                when "11"
                  message :scsi, "space : #{@scsi_extra_data.inspect}", event
                else
                  message :scsi, "**** #{@scsi_cmd_current} : #{@scsi_extra_data.inspect}", event
                end
                @scsi_cmd_index = 0
                @scsi_extra_data = []
              end
              return
            end
            # SCSI, see pie.c
            @scsi_cmd_data[@scsi_cmd_index] = event.data
            case @scsi_cmd_index
            when 0 then @scsi_cmd_current = event.data
            when 4 then @scsi_cmd_length = event.data
            when 5
              case @scsi_cmd_current
              when "00"
                raise "Bad SCSI: #{event.raw}" unless @scsi_cmd_length == "00"                
                message :scsi, "test_ready (#{@scsi_cmd_length}:#{@scsi_cmd_data.inspect})", event
              when "01" then message :scsi, "calibrate (#{@scsi_cmd_length}:#{@scsi_cmd_data.inspect})", event
              when "03" then message :scsi, "sense (#{@scsi_cmd_length}:#{@scsi_cmd_data.inspect})", event
              when "04" then message :scsi, "format (#{@scsi_cmd_length}:#{@scsi_cmd_data.inspect})", event
              when "08" then message :scsi, "read (#{@scsi_cmd_length}:#{@scsi_cmd_data.inspect})", event
              when "0a"
                message :scsi, "write (#{@scsi_cmd_length}:#{@scsi_cmd_data.inspect})", event
                @scsi_extra_count = @scsi_cmd_length.hex.to_i
                @scsi_extra_data = []
              when "15"
                message :scsi, "mode select (#{@scsi_cmd_length}:#{@scsi_cmd_data.inspect})", event
                @scsi_extra_count = @scsi_cmd_length.hex.to_i
                @scsi_extra_data = []
              when "d1"
                message :scsi, "slide (#{@scsi_cmd_length}:#{@scsi_cmd_data.inspect})", event
                @scsi_extra_count = @scsi_cmd_length.hex.to_i
                @scsi_extra_data = []
              when "dc"
                message :scsi, "set_gain_offset (#{@scsi_cmd_length}:#{@scsi_cmd_data.inspect})", event
                @scsi_extra_count = @scsi_cmd_length.hex.to_i
                @scsi_extra_data = []
              when "10", "11" # handled above
                message :scsi, "-- extra data follows (#{@scsi_cmd_length}:#{@scsi_cmd_data.inspect})", event
                @scsi_extra_count = @scsi_cmd_length.hex.to_i
                @scsi_extra_data = []
              when "0c" then message :scsi, "0x0c (#{@scsi_cmd_length}:#{@scsi_cmd_data.inspect})", event
              when "0f" then message :scsi, "read_reverse (#{@scsi_cmd_length}:#{@scsi_cmd_data.inspect})", event
              when "12" then message :scsi, "inquiry (#{@scsi_cmd_length}:#{@scsi_cmd_data.inspect})", event
              when "16" then message :scsi, "reserve_unit (#{@scsi_cmd_length}:#{@scsi_cmd_data.inspect})", event # used ?
              when "18" then message :scsi, "copy (#{@scsi_cmd_length}:#{@scsi_cmd_data.inspect})", event
              when "1a" then message :scsi, "mode sense (#{@scsi_cmd_length}:#{@scsi_cmd_data.inspect})", event
              when "1b"
                message :scsi, "scan : #{@scsi_cmd_length}:#{@scsi_cmd_data.inspect}", event
              when "1d" then message :scsi, "diag (#{@scsi_cmd_length}:#{@scsi_cmd_data.inspect})", event
              when "a8" then message :scsi, "read (#{@scsi_cmd_length}:#{@scsi_cmd_data.inspect})", event
              when "d7" then message :scsi, "read_gain_offset (#{@scsi_cmd_length}:#{@scsi_cmd_data.inspect})", event
              when "dd" then message :scsi, "read_status (#{@scsi_cmd_length}:#{@scsi_cmd_data.inspect})", event
              when "ff" then message :scsi, "0xff (#{@scsi_cmd_length}:#{@scsi_cmd_data.inspect})", event
              else
                message :scsi, "****\t\t\t #{@scsi_cmd_current} (#{@scsi_cmd_length}:#{@scsi_cmd_data.inspect})", event
              end
              @scsi_cmd_data = []
              @scsi_cmd_index = -1
            end
            @scsi_cmd_index += 1
            increment "SCSI", event.data_s
          when [0x0c, 0x0087]
            # IEEE1284 control
            # 1 byte
            # sequence 0x04 (C1284_NINIT), 0x05 (C1284_NINIT | C1284_NSTROBE)
            case event.data
            when "04" then message :ctrl, "init", event
            when "05" then message :ctrl, "strobe", event
            else
              raise "Unknown IEEE1284 control value #{event.data.inspect}"
            end
            increment "Control", event.data_s
          when [0x0c, 0x0088]
            # IEEE1284 command, see hpsj5s.c:cpp_daisy()
            # 1 byte
            # sequence: 0xaa 0x55 0x00 0xff 0x87 0x78 <cmd> 0xff
            # cmd: 0x00 - assign addr (?)
            #      0x30 - deselect all
            #      0x20+x - epp mode
            #      0xd0+x - ecp mode
            #      0xe0 - default
            case @ieee1284_cmd_index
            when 7 # command
              @ieee1284_current_cmd = event.data.hex.to_i
            when 8 # end
              unless event.data.hex.to_i == @ieee1284_cmd_sequence[@ieee1284_cmd_index]
                raise "Bad IEEE1284 command at pos 7: #{event.data}: #{event.raw}"
              end
              case @ieee1284_current_cmd
              when 0 then message :cmd, "Addr", event
              when 0x30 then message :cmd, "Reset", event
              when 0xe0 then message :cmd, "SCSI", event
              else
                message :cmd, "??? #{@ieee1284_current_cmd.to_hex}", event
              end
              @ieee1284_cmd_index = -1
            else
              unless event.data.hex.to_i == @ieee1284_cmd_sequence[@ieee1284_cmd_index]
                raise "Bad IEEE1284 command at pos #{@ieee1284_cmd_index}: have #{event.data.hex.to_i}, expect #{@ieee1284_cmd_sequence[@ieee1284_cmd_index]}: #{event.raw}"
              end
            end
            @ieee1284_cmd_index += 1
            increment "Command", event.data
          when [0x0c, 0x008c]
            # 1 byte
            # 0x84
            increment "c:8c", event.data
          else
            raise "Unknown Submission Event bRequest (expect 0x0c, have #{event.bRequest}) #{event.raw}"
          end
        else
          raise "Unknown Submission Event bmRequestType (expect 0x40, have #{event.bmRequestType}) #{event.raw}"
        end
      else
        raise "Unknown Submission Event status (expect 's', have #{event.status}) #{event.raw}"
      end
    end

    #
    # interprete Submission event
    #
    # UsbMon::Submission
    #   attr_reader :bmRequestType, :bRequest, :wValue, :wIndex, :wLength, :dtag, :data
    #
    def interprete_submission event
      case event.utd
      when "Ci"
        interprete_submission_control_input event
      when "Co"
        interprete_submission_control_output event
      when "Bi"
        interprete_submission_bulk_input event
      when "Bo"
        interprete_submission_bulk_output event
      when "Zi", "Zo", "Ii", "Io"
        STDERR.puts "*** Unhandled submission utd #{event.utd}"
      else
        raise "Unknown event type #{event.type.inspect}"
      end
    end

    #################################
    # Callback
    #
    
    # C Ci
    def interprete_callback_control_input event
      # status
      message :usb, "\t= #{event.status}", event
    end

    # C Co
    # status == 0 => Ack
    #
    def interprete_callback_control_output event     
      puts "C Co #{event.status}" unless event.status == "0"
    end

    # C Bi
    def interprete_callback_bulk_input event
      message :top, "Receive #{event.data_s}", event
    end

    # C Bo
    def interprete_callback_bulk_output event
      puts event
    end

    #
    # interprete Callback event
    #     attr_reader :dir, :bus, :device, :endpoint, :status, :dlen, :dtag, :data
    #
    def interprete_callback event
      case event.utd
      when "Ci"
        interprete_callback_control_input event
      when "Co"
        interprete_callback_control_output event
      when "Bi"
        interprete_callback_bulk_input event
      when "Bo"
        interprete_callback_bulk_output event
      when "Zi", "Zo", "Ii", "Io"
        STDERR.puts "*** Unhandled callback utd #{event.utd}"
      else
        raise "Unknown event type #{event.type.inspect}"
      end
      @state = :idle
    end
    
    #################################
    # Event
    #
    
    #
    # interprete single event
    #
    def interprete event
      @start ||= event.timestamp
      case event
      when UsbMon::Submission then interprete_submission event
      when UsbMon::Callback then interprete_callback event
      when UsbMon::Error then interprete_error event
      else
        raise "Unknown event class #{event.class}"
      end
    end
    #
    # 'run' interpreter over array of UsbMon::Event(s)
    #
    #
    def run events
      events.each do |event|        
        interprete event
      end
#      return
      puts "Statistics:"
      @counts.each do |k,v|
        puts "#{k.inspect} =>"
        i = 0
        step = 6
        while i < v.size
          puts "\t#{v[i,step]}"
          i += step
        end
      end
    end
  end
end
