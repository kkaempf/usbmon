class Ieee1284
  def Ieee1284.match_sequence stream, sequence, port
    match = 0
    co = nil
    loop do
      co = ControlOut.consume stream
      return nil unless co
      if co.port == port
        if co.value == sequence[match]
          match += 1
          break if match == sequence.size
          next
        end
      end
      match = 0
    end
    true
  end
  def Ieee1284.consume stream
    # match init sequence
    init = [0xff, 0xaa, 0x55, 0x00, 0xff, 0x87, 0x78, 0xe0]
    if Ieee1284.match_sequence stream, init, 0x0088
      # match strobe
      if Ieee1284.match_sequence stream, [0x05, 0x04], 0x0087
        # match exit
        if Ieee1284.match_sequence stream, [0xff], 0x0088
          return true
        end
      end
    end
    nil
  end
end
