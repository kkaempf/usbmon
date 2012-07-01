# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "usbmon/version"

Gem::Specification.new do |s|
  s.name        = "usbmon"
  s.version     = UsbMon::VERSION

  s.platform    = Gem::Platform::RUBY
  s.authors     = ["Klaus Kämpf"]
  s.email       = ["kkaempf@suse.de"]
  s.homepage    = "https://github.com/kkaempf/usbmon"
  s.summary     = %q{A 'usbmon' parser and DigitDia protocol interpreter}
  s.description = %q{Decompiles the DigitDia USB protocol}

#  s.requirements << %q{}

  s.add_dependency("rdoc")

  s.add_development_dependency('rake')
  s.add_development_dependency('bundler')
  
  s.rubyforge_project = "usbmon"

  s.files         = `git ls-files`.split("\n")
  s.files.reject! { |fn| fn == '.gitignore' }
  s.extra_rdoc_files    = Dir['README*', 'CHANGELOG*', 'LICENSE']
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]
end
