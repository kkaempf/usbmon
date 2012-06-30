#
# dupcheck.rb
#
# Find duplicate chains of USB events
#
#
require File.join(File.dirname(__FILE__),'usbmon')

class DupCheck
  attr_reader :events
  def initialize path
    raise "Empty path" if path.empty?
    @path = path
    File.open(path, 'r') do |file|
      @events = USBMON::Event.parse file
    end
  end
  
  # find duplicate event after pos
  # if event not given, use event at pos
  #
  # @returns - nil if not found
  #          - pos of duplicate
  #
  def find pos, event = nil
    event ||= @events[pos]
    while pos < @events.size
      pos += 1
      if @events[pos] == event
        return pos
      end
    end
    nil
  end

  # find duplicate chains, starting at pos
  def find_dups start = 0
    len = 1 # length of current chain
    dup = nil # start of duplicate
    while start < @events.size
      dup = find start
      unless dup
        start += 1
        next
      end
      loop do
        e_s = @events[start+len]
        break unless e_s
        e_d = @events[dup+len]
        break unless e_d
        break unless e_s == e_d
        len += 1
      end
      puts "Dup chain of len #{len} at #{start} and #{dup}"
      i = 0
      while i < len
#        puts "%30s | %30s" % [@events[start+i].content, @events[dup+i].content]
        i += 1
      end
      start += len
      dup = nil
      len = 1
    end
  end
end

dupcheck = DupCheck.new ARGV.shift
dupcheck.find_dups
