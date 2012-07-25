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
    def initialize
      @state = :idle
      @counts = {}
      @ieee1284_cmd_index = 0
      # cmd at index 7
      @ieee1284_cmd_sequence = [0xff, 0xaa, 0x55, 0x00, 0xff, 0x87, 0x78, 0x00, 0xff]
      @scsi_cmd_index = 0
      @scsi_extra_count = 0
    end
    
    def message msg, event
      time = (event.timestamp - @start) / 1000
      if @previous
        delta = time - @previous
      else
        delta = 0
      end
      puts "(+%5d ms) t+%5d: %s" % [delta.to_i, time.to_i, msg]
      puts "\t\t#{event.raw}"
      @previous = time
    end
    #
    # statistics
    #
    def increment what, data
      @counts[what] ||= []
      @counts[what] << data
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
      message ("\tGet status %04x,%04x" % [event.wValue,event.wIndex]), event
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
	  message "usb init bmRequestType 0x00", event
	when 0x02 # Init
	  message "usb 02 bmRequestType 0x02", event
	when 0x23 # 
	  message "usb 23 bmRequestType 0x23", event
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
                    direction = "\n\tUNKNOWN DIRECTION\n"
                  end
                  message "SCSI #{direction} slide : #{@scsi_extra_data.inspect}", event
                when "0a"
                  message "SCSI write : #{@scsi_extra_data.inspect}", event
                when "10"
                  message "SCSI mark : #{@scsi_extra_data.inspect}", event
                when "11"
                  message "SCSI space : #{@scsi_extra_data.inspect}", event
                when "15"
                  message "SCSI mode select : #{@scsi_extra_data.inspect}", event
                when "dc"
                  message "SCSI dc : #{@scsi_extra_data.inspect}", event
                else
                  message "\t\t\t\t SCSI #{@scsi_cmd_current} : #{@scsi_extra_data.inspect}", event
                end
                @scsi_cmd_index = 0
                @scsi_extra_data = []
              end
              return
            end
            # SCSI, see pie.c
            case @scsi_cmd_index
            when 0 then @scsi_cmd_current = event.data
            when 4 then @scsi_cmd_length = event.data
            when 5
              case @scsi_cmd_current
              when "00"
                raise "Bad SCSI: #{event.raw}" unless @scsi_cmd_length == "00"                
                message "SCSI reset (#{@scsi_cmd_length} bytes)", event
              when "01" then message "SCSI calibrate (#{@scsi_cmd_length} bytes)", event
              when "03" then message "SCSI sense (#{@scsi_cmd_length} bytes)", event
              when "04" then message "SCSI format (#{@scsi_cmd_length} bytes)", event
              when "08" then message "SCSI read (#{@scsi_cmd_length} bytes)", event
              when "0a", "10", "11", "15", "d1", "dc"
                @scsi_extra_count = @scsi_cmd_length.hex.to_i
                @scsi_extra_data = []
              when "0c" then message "SCSI 0c (#{@scsi_cmd_length} bytes)", event
              when "0f" then message "SCSI 0f (#{@scsi_cmd_length} bytes)", event
              when "12" then message "SCSI inquiry (#{@scsi_cmd_length} bytes)", event
              when "18" then message "SCSI 18 (#{@scsi_cmd_length} bytes)", event
              when "1a" then message "SCSI mode sense (#{@scsi_cmd_length} bytes)", event
              when "1b" then message "SCSI load/unload : #{@scsi_cmd_length} bytes", event
              when "1d" then message "SCSI diag (#{@scsi_cmd_length} bytes)", event
              when "a8" then message "SCSI read (#{@scsi_cmd_length} bytes)", event
              when "d7" then message "SCSI d7 (#{@scsi_cmd_length} bytes)", event
              when "dd" then message "SCSI dd (#{@scsi_cmd_length} bytes)", event
              when "ff" then message "SCSI ff (#{@scsi_cmd_length} bytes)", event
              else
                message "****\t\t\t SCSI #{@scsi_cmd_current} (#{@scsi_cmd_length} bytes)", event
              end
              @scsi_cmd_index = -1
            end
            @scsi_cmd_index += 1
            increment "SCSI", event.data_s
          when [0x0c, 0x0087]
            # IEEE1284 control
            # 1 byte
            # sequence 0x04 (C1284_NINIT), 0x05 (C1284_NINIT | C1284_NSTROBE)
            case event.data
            when "04" then message "Ctrl - init", event
            when "05" then message "Ctrl - strobe", event
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
              when 0 then message "Cmd - Addr", event
              when 0x30 then message "Cmd - Reset", event
              when 0xe0 then message "Cmd - SCSI", event
              else
                message "Cmd 1284 - ??? #{@ieee1284_current_cmd.to_hex}", event
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
      message "\t= #{event.status}", event
    end

    # C Co
    # status == 0 => Ack
    #
    def interprete_callback_control_output event     
      puts "C Co #{event.status}" unless event.status == "0"
    end

    # C Bi
    def interprete_callback_bulk_input event
      message "Receive #{event.data_s}", event
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
