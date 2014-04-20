class BulkIn
  attr_reader :length, :data
  def initialize stream, maxlen
    @length = 0
    @data = []
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
      break unless stream.peek(UsbMon::Submission, "Bi")
    end
  end
end
