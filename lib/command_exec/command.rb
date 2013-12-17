# encoding: utf-8
# Classes concerning command execution
module CommandExec
  # Run commands
  class Command
    private

    attr_reader :path

    public

    # @!attribute [rw] log_file
    #   Set/Get log file for command
    #
    # @!attribute [rw] options
    #   Set/Get options for the command
    #
    # @!attribute [rw] parameter
    #   Set/Get parameter for the command
    attr_accessor :log_file, :options , :parameter

    # @!attribute [r] result
    #   Return the result of command execution
    #
    # @!attribute [r] working_directory
    #   Return the working directory of the command
    attr_reader :result, :working_directory

    # Create a new command to execute
    #
    # @param [Symbol] name
    #   name of command
    #
    # @param [optional,Hash] opts
    #   options for the command
    #
    # @option opts [String] :options ('')
    #   options for the command
    #
    # @option opts [String] :secure_path (false)
    #   delete all ../ from command path
    #
    # @option opts [String] :working_directory (current working directory)
    #   working_directory for the command
    #
    # @option opts [String] :log_file ('')
    #   log file of the command
    #
    # @option opts [String,Array] :search_paths ($PATH)
    #   where to search for the command (please mind the 's' at the end.
    #
    # @option opts [String,Array] :error_detection_on (:return_code)
    #   what information should be considered for error detection,
    #   available options are :return_code, :stderr, :stdout, :log_file.
    #   You can use one or more of them.
    #
    # @option opts [Hash] :error_indicators
    #   what keywords etc. should be considered as errors.
    #
    #   You can define allowed or forbidden keywords or exit codes.
    #   To search for errors in a log file you need to provide one.
    #
    #   For each option you can provide a single word or an Array of words.
    #
    #   ```
    #   allowed_return_code: [0],
    #   forbidden_return_code: [],
    #   allowed_words_in_stderr: [],
    #   forbidden_words_in_stderr: [],
    #   allowed_words_in_stdout: [],
    #   forbidden_words_in_stdout: [],
    #   allowed_words_in_log_file: [],
    #   forbidden_words_in_log_file: [],
    #   ```
    #
    # @option opts [Symbol] :on_error_do
    #   Oh, an error happend, what to do next? Raise an error (:raise_error),
    #   Throw an error (:throw_error) or do nothing at all (:nothing, default).
    #
    # @option opts [Symbol] :run_via
    #   Which runner should be used to execute the command: :open3 (default)
    #   or :system.
    #
    # @option opts [Logger] :lib_logger
    #   The logger which is used to output information generated by the
    #   library. The logger which is provided needs to be compatible with api
    #   of the Ruby `Logger`-class.
    #
    # @option opts [Symbol] :lib_log_level
    #   What information should handled by the logger:
    #   :debug, :info, :warn, :error, :fatal, :unknown. Additionally the
    #   :silent-option is understood: do not output anything (@see README for
    #   further information).
    def initialize(cmd, opts = {})
      @opts = {
        secure_path:        false,
        options:            '',
        parameter:          '',
        working_directory:  Dir.pwd,
        log_file:           '',
        search_paths:       CommandExec.search_paths,
        error_detection_on: [:return_code],
        error_indicators:   {
          allowed_return_code:         [0],
          forbidden_return_code:       [],
          allowed_words_in_stderr:     [],
          forbidden_words_in_stderr:   [],
          allowed_words_in_stdout:     [],
          forbidden_words_in_stdout:   [],
          allowed_words_in_log_file:   [],
          forbidden_words_in_log_file: [],
        },
        on_error_do:   :nothing,
        run_via:       :open3,
        lib_logger:    nil,
        lib_log_level: :info,
      }.deep_merge opts

        if @opts[:secure_path]
          @executable = SecuredExecutable.new(cmd, search_paths: SearchPath.new(@opts[:search_paths] || cmd).to_a)
        else
          @executable = SimpleExecutable.new(cmd, search_paths: SearchPath.new(@opts[:search_paths] || cmd).to_a)
        end

        if @opts[:lib_logger].nil?
          @logger = CommandExec.logger
        else
          @logger = @opts[:lib_logger]
        end
        @logger.mode = @opts[:lib_log_level]

        @logger.debug @opts

        @options = @opts[:options]

        begin
          @path = @executable.absolute_path
        rescue [Exceptions::CommandNotFound, Exceptions::CommandIsNotAFile, Exceptions::CommandIsNotExecutable]  => e
          CommandExec.logger.fatal(e.message)
          raise
        end

        @parameter = @opts[:parameter]
        @log_file = @opts[:log_file]

        *@error_detection_on = @opts[:error_detection_on]
        @error_indicators = @opts[:error_indicators]
        @on_error_do = @opts[:on_error_do]

        @run_via = @opts[:run_via]

        @working_directory = @opts[:working_directory]
        @result = nil
    end

    # Output the textual representation of a command
    #
    # @return [String] command in text form
    def to_s
      cmd = ''
      cmd += path
      cmd += @options.blank? ? '' : " #{@options}"
      cmd += @parameter.blank? ? '' : " #{@parameter}"

      @logger.debug cmd

      cmd
    end

    # Run the program
    #
    # @raise [CommandExec::Exceptions::CommandExecutionFailed] if an error
    #   occured and `command_exec` should raise an exception in the case of an
    #   error.
    # @throw [:command_execution_failed] if an error
    #   occured and `command_exec` should throw an error (which you can catch)
    #   in the case of an error
    def run
      process = CommandExec::Process.new(lib_logger: @logger)
      process.log_file = @log_file if @log_file
      process.status = :success

      process.start_time = Time.now

      case @run_via
      when :open3
        Open3::popen3(to_s, chdir: @working_directory) do |stdin, stdout, stderr, wait_thr|
          process.stdout = stdout.readlines.map(&:chomp)
          process.stderr = stderr.readlines.map(&:chomp)
          process.pid = wait_thr.pid
          process.return_code = wait_thr.value.exitstatus
        end
      when :system
        Dir.chdir(@working_directory) do
          system(to_s)
          process.stdout = []
          process.stderr = []
          process.pid = $CHILD_STATUS.pid
          process.return_code = $CHILD_STATUS.exitstatus
        end
      else
        Open3::popen3(to_s, chdir: @working_directory) do |stdin, stdout, stderr, wait_thr|
          process.stdout = stdout.readlines.map(&:chomp)
          process.stderr = stderr.readlines.map(&:chomp)
          process.pid = wait_thr.pid
          process.return_code = wait_thr.value.exitstatus
        end
      end

      process.end_time = Time.now
      error_detector = ErrorDetector.new

      if @error_detection_on.include?(:return_code)
        error_detector.check_for process.return_code, :not_contains, @error_indicators[:allowed_return_code], tag: :return_code
        error_detector.check_for process.return_code, :contains_any, @error_indicators[:forbidden_return_code], tag: :return_code unless @error_indicators[:forbidden_return_code].blank?
      end

      if @error_detection_on.include?(:stderr)
        error_detector.check_for process.stderr , :contains_any_as_substring, @error_indicators[:forbidden_words_in_stderr], exceptions: @error_indicators[:allowed_words_in_stderr], tag: :stderr
      end

      if @error_detection_on.include?(:stdout)
        error_detector.check_for process.stdout, :contains_any_as_substring, @error_indicators[:forbidden_words_in_stdout], exceptions: @error_indicators[:allowed_words_in_stdout], tag: :stdout
      end

      if @error_detection_on.include?(:log_file)
        error_detector.check_for process.log_file, :contains_any_as_substring, @error_indicators[:forbidden_words_in_log_file], exceptions: @error_indicators[:allowed_words_in_log_file], tag: :log_file
      end

      if error_detector.found_error?
        process.status = :failed
        process.reason_for_failure = error_detector.failed_sample.tag

        case process.reason_for_failure
        when :stderr
          @logger.debug 'Error detection on stderr found an error'
        when :stdout
          @logger.debug 'Error detection on stdout found an error'
        when :return_code
          @logger.debug 'Error detection on return code found an error'
        when :log_file
          @logger.debug 'Error detection on log file found an error'
        end

        case @on_error_do
        when :nothing
          # nothing
        when :raise_error
          fail CommandExec::Exceptions::CommandExecutionFailed, 'An error occured. Please check for reason via command.reason_for_failure and/or command.stdout, comand.stderr, command.log_file, command.return_code'
        when :throw_error
          throw :command_execution_failed
        else
          # nothing
        end
      end

      @logger.debug "Result of command run #{process.status}"

      @result = process
    end

    # Run a command
    #
    # @see # initialize
    def self.execute(name, opts = {})
      command = new(name, opts)
      command.run

      command
    end
  end
end
