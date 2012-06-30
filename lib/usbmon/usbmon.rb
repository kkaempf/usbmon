# Convert USBMON capture data ('u' format) to ASCII
#

      # U                T          E P          S
      # ffff88030b7da180 3003266721 S Co:1:002:0 s 40 0c 0087 0008 0001 1 = 04
      # U - urb tag
      # T - timestamp
      # E - event type ('S'ubmission, 'C'allback, 'E'error)
      # P - pipe word (<URB type and direction>:<Bus number>:<Device address>:<Endpoint number>
      #	               Ci Co   Control input and output
      #                Zi Zo   Isochronous input and output
      #		       Ii Io   Interrupt input and output			    
      #                Bi Bo   Bulk input and output
      # S - status     ('s' - setup tag)
      #

module USBMON
  
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
    # parse 'pipe word'
    #
    def pipe word
      # P - pipe word (<URB type and direction>:<Bus number>:<Device address>:<Endpoint number>)
      values = word.split(":")
      case values[0][0,1]
      when "C" then @type = :control
      when "Z" then @type = :isochronous
      when "I" then @type = :interrupt
      when "B" then @type = :bulk
      else
	STDERR.puts "Unknown urb type #{values[0][0,1]}"
      end
      case values[0][1,1]
      when "i" then @dir = :in
      when "o" then @dir = :out
      else
	STDERR.puts "Unknown direction #{values[0][1,1]}"
      end
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
    def initialize values
      @urb = values.shift.hex
      @timestamp = values.shift.to_i
      values.shift # values[2] consumed at parse
      pipe values.shift
      @status = values.shift
    end
    public
    attr_reader :urb, :timestamp, :type, :dir, :bus, :device, :endpoint, :status, :dlen, :dtag, :data
    #
    # Check for payload equality
    #
    def == event
      self.type == event.type &&
        self.dir == event.dir &&
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
      @dlen = values.shift
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
    private
    def Event.line_parse line
      values = line.split(" ")
      # <urb> <time> <type> ...
      case values[2]
      when 'S' then return Submission.new values
      when 'C' then return Callback.new values
      when 'E' then return Error.new values
      else
	STDERR.puts "Unknown event type >#{values[2]}"
      end
    end
    public
    #
    # Parse usbmon line or file, return single (line) or Array (file) of events
    # Create correct Instance
    #
    def Event.parse input
      case input
      when IO
        out = []
        while (line = input.gets)
          line.strip!
          next if line.empty?
          next if line[0,1] == '#' # comment
          out << line_parse(line)
        end
      else
        out = line_parse input
      end
      out
    end
    #
    # string representation
    #
    def to_s
      "%016x %08d %s %s [Bus %d, Device %d, Endpoint %d]" % [@urb, @timestamp, @type, @dir, @bus, @device, @endpoint]
    end
    #
    # content to string
    #
    def content
      "%s %s [Bus %d, Device %d, Endpoint %d]" % [@type, @dir, @bus, @device, @endpoint]
    end
  end
  
  #
  # Submission event
  #
  class Submission < Event
    private
    def request_type val
      @req_type = val.hex
    end
    def request_type_s
      s = case (@req_type >> 5) & 0x03
      when 0 then "Standard"
      when 1 then "Class"
      when 2 then "Vendor"
      when 3 then "Reserved"
      end
      s << " "
      s << (((@req_type & 128) == 0) ? "->" : "<-")
      s << case @req_type & 0x1f
      when 0 then "Device"
      when 1 then "Interface"
      when 2 then "Endpoint"
      when 3 then "Other"
      else
	"Reserved"
      end
    end
    public
    attr_reader :req_type, :req, :value, :index, :length, :values, :tag
    def initialize values
      super values
      if @status == "s" # setup
	request_type values.shift
	@req = values.shift
	@value = values.shift
	@index = values.shift.hex
	@index = -(65536-@index) if @index > 32767
	@length = values.shift.hex
	self.data = values
      else
	status = @status.split ":"
	if status.size > 1
	  STDERR.puts "Status #{@status}"
	else
	  @status = @status.to_i
	end
      end
    end
    def to_s
      s = "#{super} S"
      if @status == "s"
	s << " {setup: %s r %s val %s idx %d len %d} " % [ request_type_s, @req, @value, @index, @length ]
	s << data_s
      end
      s
    end
  end

  #
  # Callback event
  #
  class Callback < Event
    def initialize values
      super values
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
    def initialize values
      super values
    end
    def to_s
      s = "#{super} E"
    end
  end

end # module

