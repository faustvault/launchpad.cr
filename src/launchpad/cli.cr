require "colorize"
require "option_parser"

module CLI
  PROGRAM = "launchpad"

  def self.display_help(help : String? = nil)
    if help
      STDERR.puts help
    else
      usage = "Usage: #{PROGRAM} <command> [-h/--help] [<options>]".colorize.bold
      STDERR.puts <<-HELP
                  launchpad is a tool developed in Crystal that allows you to easily manipulate
                  your macOS Launchpad layout using a YAML configuration file.

                  #{usage}

                  Commands:

                      extract    Extract the current Launchpad layout and dump it as YAML
                      build      Load a YAML layout and build the Launchpad database
                      help       Shows this help message"
                  HELP
    end
    STDERR.puts
    STDERR.puts <<-FOOTER.colorize.green
                Check out https://github.com/fgimian/launchpad.cr for more information about
                this tool and https://crystal-lang.org for more information about Crystal.
                FOOTER
  end

  def self.display_error(message : String, help : String? = nil)
    STDERR.puts "Error: #{message}".colorize.light_red
    STDERR.puts
    display_help(help)
  end

  def self.create_option_banner(usage : String)
    usage = "Usage: #{usage}".colorize.bold

    <<-BANNER
    #{usage}

    Options:

    BANNER
  end

  def self.extract(filename, database_path)
    puts filename
    puts database_path
  end

  def self.extract_command
    filename : String? = nil
    database_path : String? = nil

    OptionParser.parse! do |parser|
      parser.banner = create_option_banner(usage: "#{PROGRAM} extract [<options>] [<filename>]")

      parser.on("-d PATH", "--database-path=PATH",
                "The Launchpad SQLite database path") { |path| database_path = path }
      parser.on("-h", "--help", "Show this help message") { display_help(parser.to_s) }
      parser.unknown_args { |args| filename = args[0]? }

      parser.invalid_option do |option|
        display_error("#{option} is not a valid option!", help: parser.to_s)
        exit 1
      end
      parser.missing_option do |option|
        display_error("#{option} is missing a value!", help: parser.to_s)
        exit 1
      end
    end

    extract(filename, database_path)
  end

  def self.build(filename, database_path)
    puts filename
    puts database_path
  end

  def self.build_command
    filename : String? = nil
    database_path : String? = nil

    OptionParser.parse! do |parser|
      parser.banner = create_option_banner(usage: "#{PROGRAM} build [<options>] <filename>")

      parser.on("-d PATH", "--database-path=PATH",
                "The Launchpad SQLite database path") { |path| database_path = path }
      parser.on("-h", "--help", "Show this help message") { display_help(parser.to_s) }
      parser.unknown_args do |args|
        filename = args[0]?
        unless filename
          display_error("A Launchpad YAML layout filename must be provided", help: parser.to_s)
          exit 1
        end
      end

      parser.invalid_option do |option|
        display_error("#{option} is not a valid option!", help: parser.to_s)
        exit 1
      end
      parser.missing_option do |option|
        display_error("#{option} is missing a value!", help: parser.to_s)
        exit 1
      end
    end

    build(filename, database_path)
  end

  def self.run
    if ARGV.empty?
      display_help
      exit 1
    end

    command = ARGV.shift

    unless ["extract", "build", "help"].includes?(command)
      display_error("The command #{command} is not supported!")
      exit 1
    end

    case command
    when "extract" then extract_command
    when "build" then build_command
    when "help" then display_help
    end
  end
end
