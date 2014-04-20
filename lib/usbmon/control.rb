class ControlIn
  attr_reader :port, :length, :data
  def initialize stream
    ci = stream.next UsbMon::Submission, "Ci"
    @port = ci.wValue
    result = stream.next UsbMon::Callback, "Ci"
    raise "Mismatch length S:Ci/C:Ci" unless ci.dlen == result.dlen
    @length = result.dlen
    @data = result.data
    return
  end
  def value
    @data[0,2].hex
  end
end

class ControlOut
  attr_reader :port, :length, :data
  def initialize stream
    event = stream.next UsbMon::Submission, "Co"
    result = stream.next UsbMon::Callback, event.utd
    raise "Mismatch Co dlen" if event.dlen != result.dlen
    @port = event.wValue
    @length = event.dlen
    @data = event.data
#    puts "ControlOut #{self}"
  end
  def value
    @data[0,2].hex
  end
  def to_s
    "%d bytes to %04x: %s" % [@length, @port, @data]
  end
  def ControlOut.consume stream
    loop do
      begin
        return ControlOut.new stream
      rescue IOError
        break
      rescue ScriptError
        raise
      rescue NameError
        raise
      rescue Exception => e
        puts "#{stream.lnum}: #{e}"
      end
    end
  end
end