require 'watirspec'
require 'spec_helper'

class LocalConfig
  def initialize(imp)
    @imp = imp
  end

  def browser
    @browser ||= (ENV['WATIR_BROWSER'] || :chrome).to_sym
  end

  def configure
    set_webdriver
    set_browser_args
    set_guard_proc
  end

  private

  def set_webdriver
    @imp.name          = :webdriver
    @imp.browser_class = Watir::Browser
  end

  def set_browser_args
    args = create_args
    @imp.browser_args = [browser, args]
  end

  def create_args
    method = "#{browser}_args".to_sym
    args = if private_methods.include?(method)
             send method
           else
             {}
           end

    if ENV['SELECTOR_STATS']
      listener = SelectorListener.new
      args.merge!(listener: listener)
      at_exit { listener.report }
    end

    args
  end

  def set_guard_proc
    matching_guards = add_guards

    @imp.guard_proc = lambda { |args|
      args.any? { |arg| matching_guards.include?(arg) }
    }
  end

  def add_guards
    matching_guards = [:webdriver]

    matching_guards << browser
    matching_guards << [browser, Selenium::WebDriver::Platform.os]
    matching_guards << :relaxed_locate if Watir.relaxed_locate?
    matching_guards << :not_relaxed_locate unless Watir.relaxed_locate?

    if !Selenium::WebDriver::Platform.linux? || ENV['DESKTOP_SESSION']
      # some specs (i.e. Window#maximize) needs a window manager on linux
      matching_guards << :window_manager
    end
    matching_guards
  end

  def firefox_args
    ENV['FIREFOX_BINARY'] ? {options: {binary: ENV['FIREFOX_BINARY']}} : {}
  end

  def safari_args
    {technology_preview: true}
  end

  def chrome_args
    opts = {args: ["--disable-translate"]}
    opts[:options] = {binary: ENV['CHROME_BINARY']} if ENV['CHROME_BINARY']
    opts
  end

  class SelectorListener < Selenium::WebDriver::Support::AbstractEventListener
    def initialize
      @counts = Hash.new(0)
    end

    def before_find(how, _what, _driver)
      @counts[how] += 1
    end

    def report
      total = @counts.values.inject(0) { |mem, var| mem + var }
      str = "Selenium selector stats: \n"
      @counts.each do |how, count|
        str << "\t#{how.to_s.ljust(20)}: #{count * 100 / total} (#{count})\n"
      end
      Watir.logger.warn str
    end
  end
end

class RemoteConfig < LocalConfig
  def configure
    @url = ENV["REMOTE_SERVER_URL"] || begin
      require 'watirspec/remote_server'

      remote_server = WatirSpec::RemoteServer.new
      remote_server.start
      remote_server.server.webdriver_url
    end
    super
  end

  private

  def add_guards
    matching_guards = super
    matching_guards << :remote
    matching_guards << [:remote, browser]
    matching_guards
  end

  def create_args
    super.merge(url: @url)
  end
end

if ENV["REMOTE_SERVER_URL"] || ENV["USE_REMOTE"]
  RemoteConfig.new(WatirSpec.implementation).configure
else
  LocalConfig.new(WatirSpec.implementation).configure
end

WatirSpec.run!
