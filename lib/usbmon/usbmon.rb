# Convert USBMON capture data ('u' format) to ASCII
#

      # U                T          E A          S
      # ffff88030b7da180 3003266721 S Co:1:002:0 s 40 0c 0087 0008 0001 1 = 04
      # U - urb tag
      # T - timestamp
      # E - event type ('S'ubmission, 'C'allback, 'E'error)
      # A - address word (formerly 'pipe')
      #                <URB type and direction>:<Bus number>:<Device address>:<Endpoint number>
      #	               Ci Co   Control input and output
      #                Zi Zo   Isochronous input and output
      #		       Ii Io   Interrupt input and output			    
      #                Bi Bo   Bulk input and output
      # S - status     ('s' - setup tag)
      #

      # utd - urb type direction
      
module UsbMon
  
  class EventIterator
    attr_reader :lnum
    def initialize input
      @input = input
      @peek = nil
      @lnum = 0
      # separate the stream into Ci,Co,Bi, and Bo queues
      @ci_queue = Array.new
      @co_queue = Array.new
      @bi_queue = Array.new
      @bo_queue = Array.new
    end
    def bus= b
      @bus = b
    end
    def device= d
      @device = d
    end
    # push event back to queue
    def unget event
#      puts "unget(#{event}) ci #{@ci_queue.size}  co #{@co_queue.size}  bi #{@bi_queue.size}  bo #{@bo_queue.size}"
      raise if event.nil?
      case event.utd
      when "Ci"
        @ci_queue.unshift event
      when "Co"
        @co_queue.unshift event
      when "Bi"
        @bi_queue.unshift event
      when "Bo"
        @bo_queue.unshift event
      else
        raise "don't know where to unget #{event.utd}"
      end
    end
    # consume next event
    def get klass = UsbMon::Submission, utd = nil
#      puts "get@#{@lnum}(#{klass}:#{utd.inspect}) ci #{@ci_queue.size}  co #{@co_queue.size}  bi #{@bi_queue.size}  bo #{@bo_queue.size}"
      case utd
      when "Ci"
        event = @ci_queue.shift
      when "Co"
        event = @co_queue.shift
      when "Bi"
        event = @bi_queue.shift
      when "Bo"
        event = @bo_queue.shift
      when NilClass
        # looking for any submission
        [@ci_queue, @co_queue, @bi_queue, @bo_queue].each do |queue|
#          puts "Looking at queue #{queue.size}: #{queue}"
          event = queue.shift
          next unless event
#          puts "Looking at queue #{queue.size}: @#{event.lnum} #{event}"
          if event.is_a?(UsbMon::Submission)
            break
          end
          queue.unshift event
          event = nil
        end
#        puts "Using #{event} from queue" if event
      else
        raise "can't get(#{klass}:#{utd})"
      end
      if event
        raise "Event #{event.utd} does not match expected #{utd}" if utd &&  event.utd != utd
        return event
      end
      # nothing matched, get next from input stream
      loop do
        line = nil
        loop do
          break if @input.eof?
          line = @input.gets
          @lnum += 1
          line.strip!
          next if line.empty?
          next if line[0,1] == '#' # comment
          break
        end
        raise IOError unless line # EOF
        event = Event.line_parse @lnum, line
        break if (@bus.nil? || event.bus == @bus) && (@device.nil? || event.device == @device)
        # discard event, doesn't match bus/device
      end
#      puts "get(#{klass}:#{utd}) parsed #{event}"
      if !event.is_a?(klass) || (utd && event.utd != utd)
        #          puts "get(#{klass}:#{utd}) pushing back #{event}"
        # wrong class/utd
        case event.utd
        when "Ci"
          @ci_queue.push event
        when "Co"
          @co_queue.push event
        when "Bi"
          @bi_queue.push event
        when "Bo"
          @bo_queue.push event
        else
          raise "Don't know where to push #{event.class}:#{event.utd}"
        end
        #          puts "get recurse"
        return self.get klass, utd # recurse
      end
#      puts "get(#{klass}:#{utd}) => #{event}"
      event
    end
  end

  #
  # Core class - USB Event
  #
  # This class is never directly instantiated, instead
  # its #parse method is used to create Event-specific subclasses
  # such as Callback, Submission or Error
  #
  class Event
    private
    #
    # (private)
    # parse 'address word'
    #
    def address word
      # A - address word (<URB type and direction>:<Bus number>:<Device address>:<Endpoint number>)
      values = word.split(":")
      @utd = values[0]
      @bus = values[1].to_i
      @device = values[2].to_i
      @endpoint = values[3].to_i
    end
    #
    # (private)
    # Initialize Event
    #
    # Consumes 5 values
    #
    def initialize lnum, values
      @lnum = lnum
      @raw = values.join(" ")
      @urb = values.shift.hex
      @timestamp = values.shift.to_i
      values.shift # values[2] consumed at parse
      address values.shift
      @status = values.shift
    end
    public
    attr_reader :raw, :lnum, :urb, :timestamp, :utd, :bus, :device, :endpoint, :status, :dlen, :dtag, :data
    #
    # Check for payload equality
    #
    def == event
      self.utd == event.utd &&
        self.bus == event.bus &&
        self.device == event.device &&
        self.endpoint == event.endpoint &&
        self.dlen == event.dlen &&
        self.dtag == event.dtag &&
        self.data == event.data
    end
    #
    # parse data
    #
    # Consumes all values
    #
    def data= values
      return unless values
#      puts "data #{values.inspect}"
      @dlen = values.shift.to_i
      return unless @dlen
      @dtag = values.shift
      if @dtag == "="
	@data = values.join("")
      end
    end
    def data_s
      s = ""
      if @data
	ascii = ""
	@data.scan(/../).collect do |v|
	  val = v.hex
	  if val < 32 || val > 126
	    ascii << "."
	  else
	    ascii << val.chr
	  end
	  s << " #{v}"
	end
	s << " | " << ascii
      end
      s
    end
    public
    def Event.line_parse lnum, line
      values = line.split(" ")
      # <urb> <time> <type> ...
      case values[2]
      when 'S' then return Submission.new lnum, values
      when 'C' then return Callback.new lnum, values
      when 'E' then return Error.new lnum, values
      else
	STDERR.puts "Unknown event type #{values[2]}"
      end
    end
    #
    # content to string
    #
    def content
      "%s [B%dD%dE%d]" % [@utd, @bus, @device, @endpoint]
    end
    #
    # string representation
    #
    def to_s
      "%016x %08d %s" % [@urb, @timestamp, content]
    end
  end
  
  #
  # Submission event
  #
  class Submission < Event
    private
    def request_type_s
      s = case (@bmRequestType >> 5) & 0x03
      when 0 then "Standard"
      when 1 then "Class"
      when 2 then "Vendor"
      when 3 then "Reserved"
      end
      s << " "
      s << (((@bmRequestType & 128) == 0) ? "->" : "<-")
      s << case @bmRequestType & 0x1f
      when 0 then "Device"
      when 1 then "Interface"
      when 2 then "Endpoint"
      when 3 then "Other"
      else
	"Reserved"
      end
    end
    public
    attr_reader :bmRequestType, :bRequest, :wValue, :wIndex, :wLength, :dtag, :data
    def initialize lnum, values
      super lnum, values
      if @status == "s" # setup
	@bmRequestType = values.shift.hex
	@bRequest = values.shift.hex
	@wValue = values.shift.hex
	@wIndex = values.shift.hex
	@wIndex = -(65536-@wIndex) if @wIndex > 32767
	@wLength = values.shift.hex
	self.data = values
      else
	status = @status.split ":"
        self.data = values
	if status.size == 1
	  @status = @status.to_i
	end
      end
    end
    def to_s
      s = "#{super} S"
      if @status == "s"
	s << " {setup: %s req %02x val %04x idx %04x len %d} " % [ request_type_s, @bRequest, @wValue, @wIndex, @wLength ]
	s << data_s
      end
      s
    end
  end

  #
  # Callback event
  #
  class Callback < Event
    def initialize lnum, values
      super lnum, values
      self.data = values
    end
    def to_s
      s = "#{super} C"
      s << data_s
    end
  end

  #
  # Error event
  #
  class Error < Event
    def initialize lnum, values
      super lnum, values
    end
    def to_s
      s = "#{super} E"
    end
  end

end # module
