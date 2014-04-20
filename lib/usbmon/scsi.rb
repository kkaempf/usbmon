class ScsiData
  def initialize data
    @data = data
  end
  def [] idx
    if @data.is_a? String
      @data = @data.scan(/../)
    end
    begin
      @data[idx].hex
    rescue
      raise "#{@data.class}[#{idx}] failed, #{@data.size}"
    end
  end
  def to_s
    @data.inspect
  end
end

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
      data = ScsiData.new co.data
      @expected = data[4] + data[5]*0x100 + data[6]*0x10000 + data[7]*0x1000000
      bi = BulkIn.new stream, @expected
      @data = ScsiData.new bi.data
      @length = bi.length
      status = ScsiStatus.new(stream)
    else
      @expected = nil
      case @cmd # check for write
      when 0x0a, 0x15, 0xd1, 0xdc
        count = length
        data = ""
        while count > 0 do
          co = ControlOut.new stream
          raise "Write to wrong port" unless co.port == 0x0085
          data << co.data
          count -= 1
        end
        @data = ScsiData.new data
        status = ScsiStatus.new(stream)
      end
    end
    @status = status
  end
  def to_s
    "#{name} -> #{@status.to_s}"
  end
  def name
    @name ||= "%02x" % @cmd
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
    case cmd[0]
    when 0x00 then Scsi_TestReady.new cmd, status, stream
    when 0x03 then Scsi_RequestSense.new cmd, status, stream
    when 0x08 then Scsi_Read.new cmd, status, stream
    when 0x0a then Scsi_Write.new cmd, status, stream
    when 0x0f then Scsi_GetParameters.new cmd, status, stream
    when 0x15 then Scsi_ModeSelect.new cmd, status, stream
    when 0x18 then Scsi_GetCCD.new cmd, status, stream
    when 0x1b then Scsi_Scan.new cmd, status, stream
    when 0xd1 then Scsi_Slide.new cmd, status, stream
    when 0xd7 then Scsi_ReadGainOffset.new cmd, status, stream
    when 0xdc then Scsi_WriteGainOffset.new cmd, status, stream
    when 0xdd then Scsi_ReadStatus.new cmd, status, stream
    else
      Scsi.new cmd, status, stream
    end
  end
end

class Scsi_TestReady < Scsi
  def initialize cmd, status, stream
    super cmd, status, stream
    @name = "TestReady"
  end    
end

class Scsi_RequestSense < Scsi
  def initialize cmd, status, stream
    super cmd, status, stream
    @name = "RequestSense"
  end
end

class Scsi_Read < Scsi
  def initialize cmd, status, stream
    super cmd, status, stream
    @name = "Read"
  end
end

class Scsi_Write < Scsi
  def initialize cmd, status, stream
    super cmd, status, stream
    @name = "Write"
  end
end

class Scsi_GetParameters < Scsi
  def initialize cmd, status, stream
    super cmd, status, stream
    @name = "GetParameters"
  end
end

class Scsi_ModeSelect < Scsi
  def initialize cmd, status, stream
    super cmd, status, stream
    @name = "ModeSelect"
  end
end

class Scsi_GetCCD < Scsi
  def initialize cmd, status, stream
    super cmd, status, stream
    @name = "GetCCD"
  end
end

class Scsi_Scan < Scsi
  def initialize cmd, status, stream
    super cmd, status, stream
    @name = "Scan"
  end
end

class Scsi_Slide < Scsi
  def initialize cmd, status, stream
    super cmd, status, stream
    @name = "Slide"
  end
end

class Scsi_ReadGainOffset < Scsi
  def initialize cmd, status, stream
    super cmd, status, stream
    @name = "ReadGainOffset"
  end
end

class Scsi_WriteGainOffset < Scsi
  def initialize cmd, status, stream
    super cmd, status, stream
    @name = "WriteGainOffset"
  end
end

class Scsi_ReadStatus < Scsi
  def initialize cmd, status, stream
    super cmd, status, stream
    @name = "ReadStatus"
  end
  def to_s
    s = "#{@name} -> #{@status}"
    if @length == 12
      s += ", WarmingUp" if @data[5] != 0
    end
    s
  end
end
