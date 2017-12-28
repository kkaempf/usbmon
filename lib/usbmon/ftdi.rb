#
# lib/usbmon/ftdi.rb
#
# 'Interpreter' for usbmon dumps talking to a FTDI usb-serial device
#
# UsbMon::Event
#     attr_reader :urb, :timestamp, :utd, :bus, :device, :endpoint, :status, :dlen, :dtag, :data
#

module UsbMon
  #
  # tty device settings
  #
  class FtdiControl
    def initialize stream, utd
      @stream = stream
      case utd
      when "Ci"
        @msg = ControlIn.new @stream
        submission_device_to_vendor @msg.event
      when "Co"
        @msg = ControlOut.new @stream
        submission_vendor_to_device @msg.event
      else
        raise "FtdiControl: unexpected utd #{utd.inspect}"
      end
#      puts "FtdiControl #{@event}"
    end
    def submission_vendor_to_device event
      case event.bRequest
      when 0
        puts "reset"
      when 1
        printf "set control 0x%04x\n", event.wValue
      when 2
        puts "flow control"
      when 3
        printf "set baudrate 0x%04x\n", event.wValue
      when 4
        printf "set data 0x%04x\n", event.wValue
      when 5
        puts "status"
      when 6
        puts "event char"
      when 7
        puts "error char"
      when 8
        puts "set latency"
      when 9
        puts "get latency"
      else
        printf "0x40 0x%02x\n", event.bRequest
      end
    end
    def submission_device_to_vendor event
      case event.bRequest
      when 0x90
        puts "read register"
      when 0x91
        puts "write register"
      when 0x92
        puts "erase register"
      else
        printf "0xc0 0x%02x\n", event.bRequest
      end
    end
    def submission event
      puts event
      case event.bmRequestType
      when 0x40
        submission_vendor_to_device event
      when 0xc0
        submission_device_to_vendor event
      else
        printf "submission type 0x%02x\n", event.bmRequestType
      end
      callback = @stream.next
      raise "expected callback, got #{callback}" unless callback.is_a? Callback
    end
  end
  #
  # Receive
  #
  class FtdiRx
    def initialize stream
      @stream = stream
      @event = BulkIn.new @stream
      puts "FtdiRx #{@event}"
    end
  end
  #
  # Transmit
  #
  class FtdiTx
    def initialize stream
      @stream = stream
      @event = BulkOut.new @stream
      puts "FtdiTx #{@event}"
    end
  end
  class Ftdi
    attr_reader :bus, :device
    def initialize eventstream, digits = []
      @stream = eventstream
      if digits.empty?
        puts "not found - please specify bus and device"
        exit 1
      else
        require 'scanf'
        @bus = digits.shift.scanf("%d")[0]
        @device = digits.shift.scanf("%d")[0]
        puts "searching at #{@bus}:#{@device}"
      end
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
          msg = @stream.peek
          next unless msg.bus == @bus && msg.device == @device
#          puts "#{msg.bus}:#{msg.device}[#{msg.utd.inspect}]: #{msg}"
          #
          # Enpoint 0: control, 1: Rx, 2: Tx
          #
          case msg.endpoint
          when 0
            FtdiControl.new @stream, msg.utd
          when 1
            FtdiRx.new @stream
          when 2
            FtdiTx.new @stream
          else
            puts "Endpoint #{msg.endpoint}: #{@stream.next}"
          end
        rescue IOError
          raise
        rescue Exception => e
          puts "Failed at line #{@stream.lnum} with #{e}"
          puts msg
          puts e.backtrace
          break
        end
      end
    end
  end
end
