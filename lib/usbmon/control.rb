class ControlIn
  attr_reader :port, :length, :data, :event
  def initialize stream
    ci = stream.next UsbMon::Submission, "Ci"
    @event = ci
    @port = ci.wValue
    # there might be a corresponding callback
    result = stream.peek
    if result.is_a?(UsbMon::Callback) && (event.utd == "Ci")
      stream.next # consume the peek
      raise "Mismatch length S:Ci/C:Ci" unless ci.dlen == result.dlen
      @length = result.dlen
      @data = result.data
    end
  end
  def to_s
    "Ci port #{@port}, length #{@length}, data #{@data.inspect}"
  end
  def value
    @data ? @data[0,2].hex : nil
  end
  def ControlIn.consume stream
    loop do
      begin
        return ControlIn.new stream
      rescue IOError
        raise
      rescue Exception => e
        raise
      end
    end
  end
end

class ControlOut
  attr_reader :port, :length, :data, :event
  def initialize stream
    co = stream.next UsbMon::Submission, "Co"
    @event = co
    result = stream.next UsbMon::Callback, co.utd
    raise "Mismatch Co dlen" if co.dlen != result.dlen
    @port = co.wValue
    @length = co.dlen
    @data = co.data
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