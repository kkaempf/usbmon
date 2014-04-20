class ScsiStatus
  attr_reader :value
  def initialize stream
    # 1 or 2 bytes scsi status
    for i in 1..2
      # scsi status
      status = ControlIn.new stream
      raise "Expecting scsi status: #{status}" unless status.port == 0x0084
      next if status.value == 3 # scsi busy
      @value = status.value
      break
    end
  end
  def to_s
    case @value
    when 0 then "Ok"
    when 1 then "Read"
    when 2 then "Check Condition"
    when 3 then "Busy"
    when 8 then "Again"
    when 255 then "Error"
    else
      "*** Status #{@value}"
    end
  end
end

class Scsi
  attr_reader :cmd, :length, :status, :expected
  def initialize cmd, status, stream
#    puts "Scsi.new #{cmd}"
    @cmd = cmd[0]
    @name = nil
    @length = cmd[3] * 255 + cmd[4]
    if status.value == 1
      # read, set length
      co = ControlOut.new stream
      raise "SCSI read malformed length #{co.length.class}" unless co.length == 8
      data = co.data.scan(/../)
      @expected = data[4].hex + data[5].hex*0x100 + data[6].hex*0x10000 + data[7].hex*0x1000000
      @data = BulkIn.new stream, @expected
      status = ScsiStatus.new(stream)
    else
      @expected = nil
      case @cmd # check for write
      when 0x0a, 0x15, 0xd1, 0xdc
        count = length
        @data = []
        while count > 0 do
          co = ControlOut.new stream
          raise "Write to wrong port" unless co.port == 0x0085
          @data << co.data
          count -= 1
        end
        status = ScsiStatus.new(stream)
      end
    end
    @status = status
  end
  def to_s
    "SCSI %s [%04x bytes] -> %s" % [name, @length, @status.to_s]
  end
  def name
    @name ||= case @cmd
    when 0x00 then "TestReady"
    when 0x03 then "RequestSense"
    when 0x08 then "Read"
    when 0x0a then "Write"
    when 0x0f then "GetParameters"
    when 0x15 then "ModeSelect"
    when 0x18 then "GetCCD"
    when 0x1b then "Scan"
    when 0xd1 then "Slide"
    when 0xd7 then "ReadGainOffset"
    when 0xdc then "WriteGainOffset"
    when 0xdd then "ReadStatus"
    else
      "%02x" % @cmd
    end
  end
  def Scsi.consume stream
#    puts "Scsi.consume"
    # ieee1284 sequence
    Ieee1284.consume stream
#    puts "Scsi Ieee1284 match"
    cmd = []
    # 6 bytes scsi cmd
    for i in 1..6
      co = ControlOut.consume stream
#      puts "Scsi cmd #{i}:#{co.inspect}"
      return nil unless co
      if co.port != 0x0085
        raise "Non scsi cmd port %04x" % co.port
      end
      cmd << co.value
    end
#    puts "Scsi cmd #{cmd}"
    status = ScsiStatus.new stream
    Scsi.new cmd, status, stream
  end
end