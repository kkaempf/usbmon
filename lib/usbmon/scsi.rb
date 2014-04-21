class ScsiData
  attr_reader :data
  def initialize data
    @data = data
  end
  def size
    if @data.is_a? String
      @data.length / 2
    else
      @data.length
    end
  end
  def get idx
    begin
      @data[idx].hex
    rescue
      raise "#{@data.class}[#{idx}] failed, max idx is #{@data.size}"
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
  def int16 idx
    self[idx] + self[idx+1]*0x100
  end
  def int32 idx
    self[idx] + self[idx+1]*0x100 + self[idx+2]*0x10000 + self[idx+3]*0x1000000
  end
  def to_s
    @data.inspect
  end
  def ScsiData.filter_name filter
    layer = [ "Neutral", "Red", "Green", "Blue" ]
    s = ""
    for i in 0..3
      if filter & (1 << i) != 0
        s += ", " unless s.empty?
        s += layer[i]
      end
    end
    s
  end
  def ScsiData.color_name idx
    [ "Red", "Green", "Blue", "Infrared"][idx]
  end
  def ScsiData.color_format format
    case format
    when 1 then "Pixel"
    when 2 then "Line"
    when 4 then "Index"
    else
      "**** Color format #{format}"
    end
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
  attr_reader :cmd, :size, :data, :length, :status, :expected
  def initialize cmd, stream
#    puts "Scsi.new #{cmd}"
    @cmd = cmd[0]
    @name = nil
    @size = cmd[3] * 255 + cmd[4]
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
        count = @size
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
    "**** #{name} -> #{@status.to_s}"
  end
  def name
    @name ||= "%02x" % @cmd
  end

  def Scsi.consume stream, expect_cmd = nil
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
    if expect_cmd
      unless expect_cmd == cmd[0]
        raise "Expected cmd %02x, got %02x" % [expect_cmd, cmd[0]]
      end
    end
#    puts "Scsi cmd #{cmd}"
    case cmd[0]
    when 0x00 then Scsi_TestReady.new cmd, stream
    when 0x03 then Scsi_RequestSense.new cmd, stream
    when 0x08 then Scsi_Read.new cmd, stream
    when 0x0a then Scsi_Write.new cmd, stream
    when 0x0f then Scsi_GetParameters.new cmd, stream
    when 0x12 then Scsi_Inquiry.new cmd, stream
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
  def to_s
    "\tReady? -> #{@status}"
  end
end

class Scsi_RequestSense < Scsi
  def to_s
    @name = "RequestSense"
    @error = @data[0]
    @segment = @data[1]
    @key = @data[2]
    @info = @data[3, 4]
    @addlen = @data[7]
    @cmdinfo= @data[8, 4]
    @code = @data[12]
    @qualifier = @data[13]                                
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
  def to_s
    if @status.value == 0
      "Read [#{@size} lines] #{@length} of #{@expected} bytes, #{@length/@size} bytes per line"
    else
      "Read [#{@size} lines] -> #{@status}"
    end
  end
end

class Scsi_Write < Scsi
  def initialize cmd, stream
    super cmd, stream
    @type = @data[0]
    if (@data[0] & 0x80) == 0x80
      read = Scsi.consume stream, 0x08
      @data = read.data
      @size = read.size
      @length = read.length
      @expected = read.expected
      @status = read.status
    end
  end
  def to_s
    s = ((@type & 0x80) == 0x80) ? "Get" : "Set"
    s << " "
    case (@type & 0x7f)
    when 1
      s << "PowerSave"
    when 0x10
      s << "GammaTable"
    when 0x11
      s << "HalftonePattern"
    when 0x12
      s << "ScanFrame [#{@data.int16(4)}] (#{@data.int16(6)},#{@data.int16(8)})-(#{@data.int16(10)},#{@data.int16(12)})"
    when 0x13
      s << "Exposure #{ScsiData.filter_name(@data.int16(4))} to #{@data.int16(6)}%"
    when 0x14
      s << "HighlightShadow #{ScsiData.filter_name(@data.int16(4))} to #{@data.int16(6)}%"
    when 0x15
      s << "CalibrationInfo"
      size = @data[5]
      color = 0
      while color < @data[4]
        s << "\n  #{ScsiData.color_name(color)}"
        s << " type %02x" % @data[8+color*size]
        s << " send #{@data[9+color*size]}"
        s << " recv #{@data[10+color*size]}"
        s << ", #{@data[11+color*size]} lines"
        s << ", #{@data.int16(12+color*size)} pixels per line"
        color += 1
      end
      s
    when 0x16
      s << "CalibrationData"
    when 0x17
      s << "Cmd17 #{@data.int16(4)}"
    else
      raise "*** Unknown write %02x" % @type
    end    
  end
end

class Scsi_GetParameters < Scsi
  def to_s
    if @status.value == 0
      s = "GetParameters"
      s << " width #{@data.int16(0)}"
      s << ", lines #{@data.int16(2)}"
      s << ", bytes #{@data.int16(4)}"
      s << "\n   filter offsets #{@data[6]} #{@data[7]}"
      s << ", period #{@data.int32(8)}"
      s << ", rate #{@data.int16(12)}"
      s << "\n   #{@data.int16(14)} lines available"
    else
      "GetParameters -> #{@status}"
    end
  end
end

class Scsi_Inquiry < Scsi
  def to_s
    s = "Inquiry -> #{@status}"
#    s << "\n  device type #{@data[0]}"
#    s << "\n  length #{@data[4]}"
#    s << "\n  vendor #{@data[8, 8]}"
#    s << "\n  product #{@data[16, 16]}"
#    s << "\n  revision #{@data[32, 4]}"
#    s << "\n  max res X #{@data.int16(36)} Y #{@data.int16(38)}"
#    s << "\n  max width #{@data.int16(40)} height #{@data.int16(42)}"
#    s << "\n  filters %02x" % @data[44]
#    s << "\n  color depths %02x" % @data[45]
#    s << "\n  color format %02x" % @data[46]
#    s << "\n  image format %02x" % @data[48]
#    s << "\n  scan capability %02x" % @data[49]
#    s << "\n  optional devices %02x" % @data[50]
#    s << "\n  enhancements %02x" % @data[51]
#    s << "\n  gamma bits %02x" % @data[52]
#    s << "\n  last filter %02x" % @data[53]
#    s << "\n  preview scan resolution #{@data.int16(53)}"
#    s << "\n  firmware version #{@data[96,4]}"
#    s << "\n  halftones #{@data[100]}"
#    s << "\n  minimum highlight #{@data[101]}"
#    s << "\n  maximum shadow #{@data[102]}"
#    s << "\n  calibration equation #{@data[103]}"
#    s << "\n  exposure max #{@data.int16(104)}, min #{@data.int16(106)}"
#    s << "\n  (#{@data.int16(108)},#{@data.int16(110)}) - (#{@data.int16(112)}, #{@data.int16(114)})"
#    s << "\n  model #{@data[116]}"
#    s << "\n  production #{@data[120, 4]}"
#    s << "\n  timestamp #{@data[124, 20]}"
#    s << "\n  signature #{@data[144, 40]}"
    s
  end
end

class Scsi_ModeSelect < Scsi
  def to_s
    s = "Mode Select -> #{@status}"
    s << "\n  #{@data.int16(2)} dpi"
    s << ", passes %02x" % @data[4]
    s << ", color %02x" % @data[5]
    s << "\n  color format #{ScsiData.color_format(@data[6])}"
    s << ", byte order #{@data[8]}"
    s << "\n  quality:"
    quality = @data[9]
    if quality & 0x02 == 2
      s << " sharpen"
    end
    if quality & 0x08 == 8
      s << " skipShadingAnalysis"
    end
    if quality & 0x80 == 0x80
      s << " fastInfrared"
    end
    s << "\n  halftone pattern #{@data[12]}"
    s << ",  line threshold #{@data[13]}"
  end
end

class Scsi_GetCCD < Scsi
  def to_s
    if @status.value == 0
      "GetCCDMask [#{@size} lines] #{@length} of #{@expected} bytes"
    else
      "GetCCDMask -> #{@status}"
    end
  end
end

class Scsi_Scan < Scsi
  def to_s
    case @size
    when 0 then "StopScan"
    when 1 then "StartScan"
    else
      "Scan *** illegal length #{@length}"
    end
  end
end

class Scsi_Slide < Scsi
  def to_s
    case [@data[0], @data[1], @data[2], @data[3]]
    when [4,1,0,0x7c], [4,1,0,0]
      "NextSlide"
    when [5,1,0,0]
      "PreviousSlide"
    when [0x10,1,0,0]
      "LampOn"
    when [0x40,0,0,1]
      "ReloadSlide"
    else
      raise "*** Slide: %s" % @data
    end
  end
end

class Scsi_ReadGainOffset < Scsi
  def to_s
    # full scale 58981
    s = "Read Gain Offset -> #{@status}"
    if @data.nil? || @data.size < 60
      return "#{s} [Cut off]"
    end
    off = 54
    while off < 60
      if off == 54
        s += "Saturation ("
      else
        s += ", "
      end
      s += @data.int16(off).to_s
      off += 2
    end
    s += ")"
  end
end

class Scsi_WriteGainOffset < Scsi
  def to_s
    s = "Write Gain Offset -> #{@status}\n"
    s << "  ExposureTime("
    off = 0
    # 0, 2, 4 exposure time
    3.times do |i|
      s << ", " if i > 0
      s << @data.int16(off).to_s
      off += 2
    end
    s << ") Offset("
    # 6, 7, 8 offset
    3.times do |i|
      s << ", " if i > 0
      s << @data[off].to_s
      off += 1
    end
    off += 3
    s << ") Gain("
    # 12, 13, 14 gain
    3.times do |i|
      s << ", " if i > 0
      s << @data[off].to_s
      off += 1
    end
    # 15 light
    s << ") Light #{@data[15]}"
    # 16 extra
    s << ", Extra #{@data[16]}"
    # 17 double times
    s << ", DoubleTimes #{@data[17]}"
    s << "\n  Infrared["
    s << "ExposureTime #{@data.int16(18)}"
    s << ", Offset #{@data[20]}"
    s << ", Gain #{@data[22]}"
    s << "]"
  end
end

class Scsi_ReadStatus < Scsi
  def to_s
    s = "\tReadStatus -> #{@status}"
    if @length == 12
      s += ", WarmingUp" if @data[5] != 0
    end
    s
  end
end
