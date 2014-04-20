class BulkIn
  attr_reader :length, :data
  def initialize stream, length
    # S:Bi sending buffer size
    event = stream.next UsbMon::Submission, "Bi"
    bufsize = event.dlen
    # C:Bi receiving data
    result = stream.next UsbMon::Callback, "Bi"
    raise "BulkIn length mismatch, expected #{length}, got #{result.dlen}" unless result.dlen == length
    @length = length
    @data = result.data
  end
end
