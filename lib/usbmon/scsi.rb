class ScsiData
  def initialize data
    @data = data
  end
  def get idx
    begin
      @data[idx].hex
    rescue
      raise "#{@data.class}[#{idx}] failed, #{@data.size}"
    end
  end
  def [] idx, len = nil
    if @data.is_a? String
      @data = @data.scan(/../)
    end
    unless len
      get idx
    else
      res = []
      while len > 0 do
        res << get(idx)
        idx += 1
        len -= 1
      end
      res
    end
  end
  def to_s
    @data.inspect
  end
end

class ScsiStatus
  attr_reader :value
  def initialize stream
    @values = []
    # 1 or 2 bytes scsi status
    for i in 1..2
      # scsi status
      status = ControlIn.new stream
      raise "Expecting scsi status: #{status}" unless status.port == 0x0084
      @values << status.value
      next if status.value == 3 # scsi busy
      @value = status.value
      break
    end
  end
  def to_s
    s = ""
    @values.each do |value|
      s += ", " unless s.empty?
      s += case value
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
    s
  end
end

class Scsi
  attr_reader :cmd, :length, :status, :expected
  def initialize cmd, stream
#    puts "Scsi.new #{cmd}"
    @cmd = cmd[0]
    @name = nil
    @length = cmd[3] * 255 + cmd[4]
    status = ScsiStatus.new stream
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
    case cmd[0]
    when 0x00 then Scsi_TestReady.new cmd, stream
    when 0x03 then Scsi_RequestSense.new cmd, stream
    when 0x08 then Scsi_Read.new cmd, stream
    when 0x0a then Scsi_Write.new cmd, stream
    when 0x0f then Scsi_GetParameters.new cmd, stream
    when 0x15 then Scsi_ModeSelect.new cmd, stream
    when 0x18 then Scsi_GetCCD.new cmd, stream
    when 0x1b then Scsi_Scan.new cmd, stream
    when 0xd1 then Scsi_Slide.new cmd, stream
    when 0xd7 then Scsi_ReadGainOffset.new cmd, stream
    when 0xdc then Scsi_WriteGainOffset.new cmd, stream
    when 0xdd then Scsi_ReadStatus.new cmd, stream
    else
      Scsi.new cmd, stream
    end
  end
end

class Scsi_TestReady < Scsi
  def initialize cmd, stream
    super cmd, stream
    @name = "\tTestReady"
  end    
end

class Scsi_RequestSense < Scsi
  def initialize cmd, stream
    super cmd, stream
    @name = "RequestSense"
    @error = @data[0]
    @segment = @data[1]
    @key = @data[2]
    @info = @data[3, 4]
    @addlen = @data[7]
    @cmdinfo= @data[8, 4]
    @code = @data[12]
    @qualifier = @data[13]                                
  end
  def to_s
    s = "Sense: Err %02x, " % @error
    key_s = [ "NoSense", "RecoveredError", "NotReady", "MediumError",
              "HardwareError", "IllegalRequest", "UnitAttention", "DataProtect",
              "BlankCheck", "VendorSpecific", "CopyAborted", "AbortedCommand",
              "Equal", "VolumeOverflow", "Miscompare", "Completed"]
    if @key >= key_s.size
      raise "#{s}**** Key #{@key} too big"
    end
    s += "%02x:%s, " % [@key, key_s[@key]]
    s += case [@key, @code, @qualifier]
      when [2, 4, 1] then "Logical unit is in the process of becoming ready"
      when [6, 0x1a, 0] then "Invalid field in parameter list"
      when [6, 0x20, 0] then "Invalid command operation code"
      when [6, 0x82, 0] then "Calibration disable not granted"
      when [6, 0, 6] then "I/O process terminated"
      when [6, 0x26, 0x82] then "MODE SELECT value invalid: resolution too high (vs)"
      when [6, 0x26, 0x83] then "MODE SELECT value invalid: select only one color (vs)"
      else
        "Code %02x, Qualifier %02x" % [@code, @qualifier]
      end
    s
  end
end

class Scsi_Read < Scsi
  def initialize cmd, stream
    super cmd, stream
    @name = "Read"
  end
end

class Scsi_Write < Scsi
  def initialize cmd, stream
    super cmd, stream
    @name = "Write"
  end
end

class Scsi_GetParameters < Scsi
  def initialize cmd, stream
    super cmd, stream
    @name = "GetParameters"
  end
end

class Scsi_ModeSelect < Scsi
  def initialize cmd, stream
    super cmd, stream
    @name = "ModeSelect"
  end
end

class Scsi_GetCCD < Scsi
  def initialize cmd, stream
    super cmd, stream
    @name = "GetCCD"
  end
end

class Scsi_Scan < Scsi
  def initialize cmd, stream
    super cmd, stream
    @name = "Scan"
  end
end

class Scsi_Slide < Scsi
  def initialize cmd, stream
    super cmd, stream
    case [@data[0], @data[1], @data[2], @data[3]]
    when [4,1,0,0x7c]
      @name = "NextSlide"
    when [5,1,0,0]
      @name = "PreviousSlide"
    when [0x10,1,0,0]
      @name = "LampOn"
    when [0x40,0,0,1]
      @name = "ReloadSlide"
    else
      raise "*** Slide: %s" % @data
    end
  end
end

class Scsi_ReadGainOffset < Scsi
  def initialize cmd, stream
    super cmd, stream
    @name = "ReadGainOffset"
  end
end

class Scsi_WriteGainOffset < Scsi
  def initialize cmd, stream
    super cmd, stream
    @name = "WriteGainOffset"
  end
end

class Scsi_ReadStatus < Scsi
  def initialize cmd, stream
    super cmd, stream
    @name = "\tReadStatus"
  end
  def to_s
    s = "#{@name} -> #{@status}"
    if @length == 12
      s += ", WarmingUp" if @data[5] != 0
    end
    s
  end
end
