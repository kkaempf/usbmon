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
    def initialize eventstream
      @stream = eventstream
    end
    
    def debug= level
      @debug = level if level > 0
    end

    #
    # consume event stream
    #
    def consume
      loop do
        begin
          scsi = Scsi.consume @stream
          break unless scsi
          if @debug
            puts "#{@stream.lnum} : #{scsi}"
          else
            puts scsi
          end
        rescue IOError
          raise
        rescue Exception => e
          puts "Failed at line #{@stream.lnum} with #{e}"
          puts e.backtrace
          break
        end
      end
    end
  end
end
