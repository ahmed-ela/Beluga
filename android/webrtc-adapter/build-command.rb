require 'digest'
require 'json'

# Bounded offline compiler/descriptor commands only; no device or runtime operations.
module AdapterBuildCommand
  PS = '/bin/ps'
  PS_SHA = '472992c470606d28f577590decfecd7f4a20f832fd92c671bebc6d44790b5d02'
  def self.now; Process.clock_gettime(Process::CLOCK_MONOTONIC); end
  def self.reap(pid)
    Process.waitpid2(pid, Process::WNOHANG)&.last
  rescue Errno::ECHILD
    nil
  end
  # Exact bounded UID+PGID readback used by operator-v18.rb.
  def self.alive?(pid)
    r, w = IO.pipe
    probe = Process.spawn(PS, '-axo', 'pgid=,uid=', in: '/dev/null', out: w, err: '/dev/null')
    w.close
    output = +''; status = nil; deadline = now + 2
    begin
      loop do
        chunk = r.read_nonblock(65_536, exception: false)
        output << chunk if chunk.is_a?(String)
        raise 'Process inventory exceeds bound' if output.bytesize > 1_048_576
        status ||= reap(probe)
        break if status && chunk.nil?
        raise 'Process readback deadline' unless now < deadline
        sleep 0.01 if chunk == :wait_readable
      end
    ensure
      r.close
      unless status
        Process.kill('KILL', probe) rescue Errno::ESRCH
        reap(probe)
      end
    end
    raise 'Process group readback failed' unless status.success?
    output.lines.any? { |line| group, uid = line.split.map(&:to_i); group == pid && uid == Process.uid }
  end
  def self.retire(pid)
    %w[TERM KILL].each do |signal|
      reap(pid); break unless alive?(pid)
      Process.kill(signal, -pid) rescue Errno::ESRCH
      deadline = now + 2
      while alive?(pid) && now < deadline
        reap(pid); sleep 0.05
      end
    end
    reap(pid)
    !alive?(pid)
  end
  def self.run(argv:, environment:, stdout:, stderr:, timeout:, cwd:, input: '', output_limit: 50 * 1_048_576)
    raise 'Process readback tool changed' unless Digest::SHA256.file(PS).hexdigest == PS_SHA
    raise 'Only small memory-only stdin supported' unless input.bytesize <= 512
    paths = [stdout, stderr].uniq
    pid = nil; status = nil; error = nil; group_gone = false; interrupted = false
    output = {}; reader = nil; writer = nil; offset = 0
    old_signals = {}
    begin
      %w[INT TERM].each { |name| old_signals[name] = Signal.trap(name) { interrupted = true; raise Interrupt } }
      paths.each { |path| output[path] = File.open(path, 'wx', 0600) }
      reader, writer = IO.pipe unless input.empty?
      deadline = now + timeout
      pid = Process.spawn(environment, *argv, chdir: cwd, unsetenv_others: true, pgroup: true,
        in: reader || '/dev/null', out: output.fetch(stdout), err: output.fetch(stderr))
      reader&.close; reader = nil
      loop do
        if writer
          written = writer.write_nonblock(input.byteslice(offset, input.bytesize - offset), exception: false)
          offset += written if written.is_a?(Integer)
          if offset == input.bytesize
            writer.close; writer = nil
          end
        end
        raise 'Command output bound' if paths.sum { |path| File.size(path) } > output_limit
        status = reap(pid); break if status
        raise 'Command deadline' unless now < deadline
        sleep 0.05
      end
    rescue Exception => caught
      error = caught
    ensure
      old_signals.each_key { |name| Signal.trap(name) { interrupted = true } }
      reader&.close rescue nil
      writer&.close rescue nil
      begin
        group_gone = pid.nil? || retire(pid)
        raise 'Owned command group remains' unless group_gone
        raise 'Command output bound' if paths.select { |path| File.file?(path) }.sum { |path| File.size(path) } > output_limit
      rescue Exception => cleanup_error
        error ||= cleanup_error
      ensure
        output.each_value { |file| file.close rescue nil }
        input.replace("\0" * input.bytesize) unless input.empty? || input.frozen?
        begin
          receipt = { pid: pid, exitCode: status&.exitstatus, processGroupGone: group_gone,
            interrupted: interrupted, errorClass: error&.class&.name }
          File.open(stdout + '.process.json', 'wx', 0600) { |file| file.write(JSON.generate(receipt) + "\n") }
        ensure
          old_signals.each { |name, handler| Signal.trap(name, handler) }
        end
      end
    end
    raise error if error
    raise Interrupt if interrupted
    raise 'Command failed' unless status&.success?
    status
  end
end
