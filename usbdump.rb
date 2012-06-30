#
# usbdump.rb
#
# Dump USBMON file to STDOUT
#
# Usage:
#   usbdump.rb                      # Reads from stdin
#   usbdump.rb <usbmon-file1> ...   # Reads from file(s)
#

require File.join(File.dirname(__FILE__),'usbmon')

class UsbDump
  def initialize path=nil
    if path
      raise "Empty path" if path.empty?
      @path = path
      @file = File.open(path, 'r')
      raise "Can't open #{path}" unless path
    else
      @file = STDIN
      STDERR.puts "Reading from stdin"
    end
  end
  
  def dump to=STDOUT
    events = USBMON::Event.parse @file
    events.each { |e| puts e }
  end
end

if ARGV.size == 0
  dump = UsbDump.new
  dump.dump
else
  ARGV.each do |path|
    dump = UsbDump.new path
    dump.dump
  end
end

