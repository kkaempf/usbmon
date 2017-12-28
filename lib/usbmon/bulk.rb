class BulkIn
  attr_reader :length, :data
  def initialize stream, maxlen=512
    @length = 0
    @data = ""
    # assemble multiple Bi up to maxlen
    loop do
      # S:Bi sending buffer size
      event = stream.next UsbMon::Submission, "Bi"
      bufsize = event.dlen
      # C:Bi receiving data
      result = stream.next UsbMon::Callback, "Bi"
      @length += result.dlen
      @data << result.data
      if @length > maxlen
        raise "BulkIn length #{@length} exceeds maximum #{maxlen}"
      elsif @length == maxlen
        break
      end
      peek = stream.peek(UsbMon::Submission, "Bi")
      break unless peek
    end
  end
  def to_s
    "BulkIn #{@length} bytes: #{@data.inspect}"
  end
end

class BulkOut
  attr_reader :length, :data
  def initialize stream, maxlen = 512
    @length = 0
    @data = ""
    # assemble multiple Bo up to maxlen
    loop do
      # S:Bo sending data
      event = stream.next UsbMon::Submission, "Bo"
#      puts "BulkOut S #{event.dlen}:#{event.data}"
#      puts "BulkOut S #{event.inspect}"
      @length = event.dlen
      @data = event.data
      # C:Bo receiving size
      result = stream.next UsbMon::Callback, "Bo"
#      puts "BulkOut C #{result.inspect}"
      if @length != result.dlen
        raise "BulkOut sent #{@length}, acknowledged #{result.dlen}"
      end
      if @length > maxlen
        raise "BulkIn length #{@length} exceeds maximum #{maxlen}"
      elsif @length == maxlen
        break
      end
      peek = stream.peek(UsbMon::Submission, "Bo")
      break unless peek
    end
  end
  def to_s
    "BulkOut #{@length} bytes: #{@data.inspect}"
  end
end
