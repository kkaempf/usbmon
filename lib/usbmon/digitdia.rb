#
# lib/usbmon/digitdia.rb
#
# 'Interpreter' for usbmon dumps talking to a 'DigitDia' slide scanner
#
# UsbMon::Event
#     attr_reader :urb, :timestamp, :type, :dir, :bus, :device, :endpoint, :status, :dlen, :dtag, :data
#

module UsbMon
  class DigitDia
    def initialize
    end
    #
    # interprete Callback event
    #
    def interprete_callback event
    end
    
    #
    # interprete Error event
    #
    def interprete_error event
    end
    
    #
    # interprete Submission event
    #
    def interprete_submission event
      case event.type
      when :control
      when :isochronous
      when :interrupt
      when :bulk
      else
        raise "Unknown event type #{event.type.inspect}"
      end
    end

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
    end
  end
end
