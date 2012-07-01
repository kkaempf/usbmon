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
    end
    #
    # statistics
    #
    def increment what
      @counts[what] ||= 0
      @counts[what] += 1
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
    end

    def interprete_submission_bulk_output event
    end

    def interprete_submission_control_input event
      unless @state == :idle
        raise "Bad state #{@state}"
      end
      @state = :await_callback
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
        if event.bmRequestType == 0x40 # Vendor -> Device
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
            increment "4:82"
          when [0x0c, 0x0085]
            # SCSI ?
            increment "c:85"
          when [0x0c, 0x0087]
            # 1 byte
            increment "c:87"
          when [0x0c, 0x0088]
            # 1 byte
            increment "c:88"
          when [0x0c, 0x008c]
            # 1 byte
            increment "c:8c"
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
        raise "Unhandled submission utd #{event.utd}"
      else
        raise "Unknown event type #{event.type.inspect}"
      end
    end

    #################################
    # Callback
    #
    
    def interprete_callback_control_input event
    end

    def interprete_callback_control_output event
    end

    def interprete_callback_bulk_input event
    end

    def interprete_callback_bulk_output event
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
        raise "Unhandled callback utd #{event.utd}"
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
      puts "Statistics: #{@counts.inspect}"
    end
  end
end
