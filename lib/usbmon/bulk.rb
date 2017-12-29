class BulkIn
  attr_reader :length, :data
  def initialize stream, maxlen=512
    @length = 0
    @data = ""
    # assemble multiple Bi up to maxlen
    loop do
      # S:Bi sending buffer size
      event = stream.get UsbMon::Submission, "Bi"
      bufsize = event.dlen
#      puts "BulkIn.new submission #{event}"
      # C:Bi receiving data
      result = stream.get UsbMon::Callback, "Bi"
#      puts "BulkIn.new callback #{result}"
      @length += result.dlen
      @data << result.data
      if @length > maxlen
        raise "BulkIn length #{@length} exceeds maximum #{maxlen}"
      elsif @length == maxlen
        break
      end
      break
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
      event = stream.get UsbMon::Submission, "Bo"
#      puts "BulkOut S #{event.dlen}:#{event.data}"
#      puts "BulkOut S #{event.inspect}"
      @length = event.dlen
      @data = event.data
      # C:Bo receiving size
      result = stream.get UsbMon::Callback, "Bo"
#      puts "BulkOut C #{result.inspect}"
      if @length != result.dlen
        raise "BulkOut sent #{@length}, acknowledged #{result.dlen}"
      end
      if @length > maxlen
        raise "BulkIn length #{@length} exceeds maximum #{maxlen}"
      elsif @length == maxlen
        break
      end
      break
    end
  end
  def to_s
    "BulkOut #{@length} bytes: #{@data.inspect}"
  end
end
