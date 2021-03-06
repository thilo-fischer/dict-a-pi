#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

# Copyright (c) 2016-2017  Thilo Fischer.
#
# This file is part of dictapi.
#
# dictapi is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# 
# dictapi is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with tobak.  If not, see <http://www.gnu.org/licenses/>.

class StateMachineContext
  attr_accessor :fork, :pipe, :speed, :pos
  def initialize
    reset
  end
  def reset
    @fork = nil
    @pipe = nil
    @speed = 1.0
    @pos = Position.new
  end
end # class StateMachineContext

# forward declarations
class StateBase; end
class StateInitial < StateBase; end

##
# Not a State the state machine should ever enter. Base class that
# implements the methods that provide the actual operations to be used
# by the chlid classes that implement the actual states.  This would
# be an abstract class if one could have abstact classes in Ruby.
class StateBase
  
  def method_missing(method_name, *args)
    if %w(play record pause resume stop speed seek seek_marker set_marker rm_marker delete reset open load).include? method_name
      warn "invalid operation `#{method_name}' for current state `#{self.class.name}'"
      self
    else
      super
    end
  end
  
  # methods to be implemented by child classes:
  # play
  # record
  # pause
  # resume
  # stop
  # speed
  # seek
  # seek_marker
  # set_marker
  # rm_marker
  # delete
  # reset
  # open (only InitialState)
  # load (only StoppedState)

  private
  # helper methods
  # XXX move to separate class or to module? (If moving to module: make classes including the module implicitly include +Singleton+??)
  def record_command(cmd, *args)
    puts "#{cmd} #{args.join(', ')}"
  end
  def run_recorder(ctx)
    file = File.join(AUDIO_DIR, "#{DateTime.now.strftime('%Y-%m-%d_%H-%M-%S_%L_%z')}.#{FILE_FORMAT}")
    new_slice = ASlice.new(file)
    if ctx.pos.slice
      latched_offset = ctx.pos.slice.insert(ctx.pos.offset, new_slice)
      ctx.pos.timecode += latched_offset - ctx.pos.offset
    end
    ctx.pos.slice = new_slice
    ctx.pos.offset = 0
    dbg_dump_slices(ctx.pos.slice)
    ctx.pipe = IO.popen("rec '#{file}'", "r+")
    record_command(:load, file)
  end
  def stop_recorder(ctx)
    dbg "stop recorder with PID #{ctx.pipe.pid.inspect}"
    Process.kill("SIGINT", ctx.pipe.pid)

    file = ctx.pos.slice.file
    dbg "polling for file `#{file}' ..."
    sleep(0.1) until File.exist?(file)
    dbg "=> file `#{file}' exists"

    system("sox '#{file}' '#{reverse_filename(file)}' reverse") or warn "failed to create reverse file"
    
    ctx.pos.slice.update_file_duration
    ctx.pos.slice.duration = ctx.pos.slice.file_duration
    ctx.pos.offset = ctx.pos.slice.duration
    ctx.pos.timecode += ctx.pos.slice.duration
    record_command(:seek, ctx.pos.timecode)
  end
  def pause_recorder(ctx)
    stop_recorder(ctx)
  end
  def resume_recorder(ctx)
    run_recorder(ctx)
  end
  def start_playback(ctx, file, from, to)
    cmdline = "|mplayer -slave -input nodefault-bindings -noconfig all -quiet -af scaletempo -speed #{ctx.speed.abs} -ss #{from/1000.0} -endpos #{to/1000.0} '#{file}'"
    dbg_dump_position(ctx.pos)
    dbg("call `#{cmdline}'")
    ctx.pipe = open(cmdline, "w+")
    # block until mplayer has started
    tmp = ctx.pipe.gets
    dbg("pipe.gets returned `#{tmp}'")
  end
  def run_player(ctx, direction = nil)
    start_offset = ctx.pos.slice.offset + ctx.pos.offset
    endpos = ctx.pos.slice.offset + ctx.pos.slice.duration
    file = ctx.pos.slice.file
    if direction
      raise unless direction == :forward or direction == :reverse
    elsif ctx.speed > 0
      direction = :forward
    elsif ctx.speed < 0
      direction = :reverse
      file = reverse_filename(file)
      start_offset = ctx.pos.slice.file_duration - start_offset
      endpos = ctx.pos.slice.file_duration - ctx.pos.slice.offset
    else
      warn "invalid speed value (0.0) when run_player"
      return
    end
    @continue_playback = true
    start_playback(ctx, file, start_offset, endpos)
    Thread.new do
      while @continue_playback
        Process.waitpid(ctx.pipe.pid)
        dbg(" *** mplayer reached end of file")
        $mutex.synchronize {
          dbg(" *** mplayer reached end of file")
          break unless @continue_playback
          if direction == :forward
            if ctx.pos.next_slice?
              ctx.pos.go_next_slice
              start_offset = ctx.pos.slice.offset
              endpos = ctx.pos.slice.offset + ctx.pos.slice.duration
              file = ctx.pos.slice.file
            else
              dbg(" *** reached end of last slice")
              ctx.pos.go_slice_end
              @continue_playback = false
            end
          else
            if ctx.pos.prev_slice?
              ctx.pos.go_prev_slice
              ctx.pos.go_slice_end
              endpos = ctx.pos.slice.file_duration - ctx.pos.slice.offset
              start_offset = endpos - ctx.pos.slice.duration
              file = reverse_filename(ctx.pos.slice.file)
            else
              dbg(" *** reached beginning of first slice")
              ctx.pos.go_slice_begin
              @continue_playback = false
            end
          end # direction
          start_playback(ctx, file, start_offset, endpos) if @continue_playback          
        }
      end # while-loop
      $mutex.synchronize {
        if @continue_playback
          #record_command(:seek, ctx.pos.timecode)
          #@continue_playback = false
          # => will be done throgh +process("stop")+
          process("stop")
        end
      }
    end # thread-block
  end # def run_player
  def stop_player(ctx)
    pause_player(ctx) # to adapt ctx.pos
    @continue_playback = false
    player_send_command(ctx.pipe, "quit")
    begin
      Process.waitpid(ctx.pipe.pid)
    rescue Errno::ECHILD
      # seems like mplayer already quit -> ignore
      nil
    end
    record_command(:seek, ctx.pos.timecode)
  end
  def pause_player(ctx)
    flush_pipe(ctx.pipe)
    unless player_send_command(ctx.pipe, "pausing get_time_pos")
      # TODO set pause flag that makes mplayer thread loop pause ?
      return
    end
    time_pos = nil
    until time_pos
      begin
        line = ctx.pipe.readline
      rescue EOFError
        warn "seems mplayer quit while we were awaiting time_pos"
        return
      end
      dbg("awaiting time_pos, got: `#{line}'")
      line =~ /ANS_TIME_POSITION=(\d+\.\d)/
      time_pos = $1
    end
    file_offset = time_pos.to_f * 1000
    # if Process.waitpid(ctx.pipe.pid, Process::WNOHANG) ... FIXME
    if ctx.speed < 0
      slice_offset = ctx.pos.slice.offset + ctx.pos.slice.duration - file_offset
    else
      slice_offset = file_offset - ctx.pos.slice.offset
    end
    slice_offset = ctx.pos.latch_offset(slice_offset)
    ctx.pos.go_slice_offset(slice_offset)
    record_command(:seek, ctx.pos.timecode)
  end
  def resume_player(ctx)
      # `pause' command pauses and unpauses => XXX ensure mplayer is in pause mode before passing it the `pause' command to resume
    player_send_command(ctx.pipe, "pause")
  end
  def abs_speed_value(ctx, value, mode = :absolute)
    abs_val = case mode
              when :relative
                ctx.speed + value
              when :absolute
                value
              else
                warn "invalid speed mode: `#{mode}'"
                1
              end
    # restrict to max speed value range supported by mplayer
    if abs_val > 0
      abs_val =  0.01 if abs_val < 0.01
      abs_val =  100  if abs_val > 100
    else
      abs_val = -0.01 if abs_val > -0.01
      abs_val = -100  if abs_val < -100
    end
    abs_val
  end
  def speed_player(ctx, value)
    # change playback direction if speed changes from negative to positive value or vice verse
    if (value > 0 and ctx.speed <= 0) or (value < 0 and ctx.speed >= 0)
      stop_player(ctx)
      ctx.speed = value
      run_player(ctx)
    else
      player_send_command(ctx.pipe, "speed_set #{value.abs}")
      flush_pipe(ctx.pipe)
      ctx.speed = value
    end
  end
  def player_send_command(pipe, cmd)
    dbg("player_send_command: `#{cmd}'")
    begin
      pipe << cmd << "\n"
      return true
    rescue Errno::EPIPE
      warn "Failed to send command to MPlayer slave: `#{cmd}'. Seems MPlayer already quit."
    end
    false
  end
  def flush_pipe(pipe)
    begin
      while str = pipe.read_nonblock(4096)
        dbg("FLUSHING `#{str}'")
      end
    rescue SystemCallError
      dbg("fushed pipe content")
    rescue EOFError
      dbg("flushing pipe -> END OF FILE")      
    end
  end
  def reverse_filename(filename)
    #ext = extname(filename)
    filename.sub(/(.*)\.(.*?)$/, '\1.reverse.\2')
  end
end # class StateBase

##
# System starts in this state and enters this state after every
# loading of another file.
class StateInitial < StateBase
  include Singleton
  def record(ctx)
    run_recorder(ctx)
    StateRecording.instance
  end
  def open(ctx, record_filename)
    state_stopped = StateStopped.instance
    File.open(record_filename, "r") do |f|
      while l = f.gets
        case l
        when /^((.*)\s*>)?\s*load\s+(.*)$/
          # timestamp = $1
          state_stopped.load(ctx, $3)
        when /^((.*)\s*>)?\s*seek\s+(.*)$/
          # timestamp = $1
          state_stopped.seek(ctx, $3.to_i)
        else
          warn "ignoring line `#{l.chomp}'"
        end
      end
    end
    if ctx.pos.slice
      # looks like at least some of the open was successful
      state_stopped
    else
      self
    end
  end
  def reset(ctx)
    self
  end
end # class StateInitial

class StateDefault < StateBase
  include Singleton
  def play(ctx)
    run_player(ctx)
    StatePlaying.instance
  end
  def record(ctx)
    run_recorder(ctx)
    StateRecording.instance
  end
  # missing methods invalid for this state:
  # pause
  # resume
  # stop
  def speed(ctx, value, mode = :absolute)
    ctx.speed = abs_speed_value(ctx, value, mode)
    self
  end
  def seek(ctx, position, mode = :absolute)
    new_state = stop(ctx)
    case mode
    when :absolute
      ctx.pos.seek(position)
    when :relative
      ctx.pos.seek(ctx.pos.timecode + position)
    when :end_offset
      ctx.pos.seek_end(position)
    else
      raise "programming error"
    end
    record_command(:seek, ctx.pos.timecode)
    new_state
  end
  # If count is > 0, seek to position of count'th next marker.
  # If count is < 0, seek to position of count'th previous marker.
  # If count is == 0, seek to position of nearest marker.
  def seek_marker(ctx, count)
    pos = ctx.pos

    raise "programming error" if pos.timecode < pos.slice_begin or pos.timecode > pos.slice_end

    slice_marks = pos.slice.find_marker(pos.offset)

    if count == 0 and slice_marks.key?(:accurate)
      return seek(ctx, pos.slice_begin + slice_marks[:accurate].offset)
    end

    prev_mark = nil
    prev_mark_timecode = nil
    prev_mark_slice = pos.slice
    prev_mark_slice_begin = pos.slice_begin
    if count <= 0
      if slice_marks.key?(:prev)
        prev_mark = slice_marks(:prev)
      else
        while prev_mark == nil do
          prev_mark_slice = prev_mark_slice.predecessor
          break if prev_mark_slice == nil
          prev_mark_slice_begin -= prev_mark_slice.duration
          prev_mark = prev_mark_slice.markers.last unless prev_mark_slice.markers.empty?
        end
      end
    end
    prev_mark_timecode = prev_mark_slice_begin + prev_mark.offset if prev_mark

    next_mark = nil
    next_mark_timecode = nil
    next_mark_slice = pos.slice
    next_mark_slice_begin = pos.slice_begin
    if count >= 0
      if slice_marks.key?(:next)
        next_mark = slice_marks(:next)
      else
        while next_mark == nil do
          next_mark_slice_begin += next_mark_slice.duration
          next_mark_slice = next_mark_slice.successor
          break if next_mark_slice == nil
          next_mark = next_mark_slice.markers.first unless next_mark_slice.markers.empty?
        end
      end
    end
    next_mark_timecode = next_mark_slice_begin + next_mark.offset if next_mark

    if count == 0
      if prev_mark
        if next_mark
          if pos.timecode - prev_mark_timecode <= next_mark_timecode - pos.timecode
            return seek(ctx, prev_mark_timecode)
          else
            return seek(ctx, next_mark_timecode)
          end
        else
          return seek(ctx, prev_mark_timecode)
        end
      else
        if next_mark
          return seek(ctx, next_mark_timecode)
        else
          warn "seek_marker failed, no marker found"
          return self
        end
      end
    elsif count > 0
      if next_mark
        # FIXME allow to seek over more than just one marker
        return seek(ctx, next_mark_timecode)
      else
        return seek(ctx, 0, :end_offset)
      end
    elsif count < 0
      if prev_mark
        # FIXME allow to seek over more than just one marker
        return seek(ctx, prev_mark_timecode)
      else
        return seek(ctx, 0, :absolute)
      end      
    else
      raise "programming error"
    end
    self
  end # def seek_marker
  def set_marker(ctx, *args)
    # TODO args
    ctx.pos.slice.set_marker(ctx.pos.offset)
    self
  end
  def rm_marker(ctx, *args)
    warn "TODO not yet implemented"
    self
  end
  def delete(ctx, *args)
    # TODO
    raise "not yet implemented"
    ## TODO arguments
    #pos = ctx.pos
    #offset = pos.offset
    #slice = pos.slice
    #from_marker = slice.marker_before(offset)
    #to_marker = slice.marker_at_or_after(offset)
    #if from_marker and to_marker
    #  slice.delete(from_marker.offset, to_marker.offset)
    #end
  end
  def reset(ctx)
    ctx.reset
    StateInitial.instance
  end
end # class StateDefault

class StatePlaying < StateDefault
  include Singleton
  def play(ctx)
    self
  end
  def record(ctx)
    stop(ctx).record(ctx)
  end
  def pause(ctx)
    pause_player(ctx)
    StatePlayingPause.instance
  end
  def stop(ctx)
    stop_player(ctx)
    StateStopped.instance
  end
  def speed(ctx, value, mode = :absolute)
    abs_value = abs_speed_value(ctx, value, mode)
    speed_player(ctx, abs_value)
    self
  end
  def seek(ctx, *args)
    # TODO args
    tmp_state = stop(ctx)
    super
    tmp_state.play(ctx)
  end
  def seek_marker(ctx, count)
    # TODO args
    pause_player(ctx)
    super
    resume_player(ctx)
    self
  end
  def set_marker(ctx, *args)
    # TODO args
    pause_player(ctx)
    super
    resume_player(ctx)
    self
  end
  def delete(ctx)
    stop(ctx).delete(ctx)
  end
  def reset(ctx)
    stop_player(ctx)
    super
  end
end # class StatePlaying

class StatePlayingPause < StateDefault
  include Singleton
  def play(ctx)
    resume_player(ctx)
    StatePlaying.instance
  end
  def record(ctx)
    stop(ctx).record(ctx)
  end
  def pause(ctx)
    return self
  end
  def resume(ctx)
    resume_player(ctx)
    StatePlaying.instance
  end
  def stop(ctx)
    stop_player(ctx)
    StateStopped.instance
  end
  def speed(ctx, value, mode = :absolute)
    abs_value = abs_speed_value(ctx, value, mode)
    speed_player(ctx, abs_value)
    self
  end
  def delete(ctx)
    stop(ctx).delete(ctx)
  end
  def reset(ctx)
    stop_player(ctx)
    super
  end
end # class StatePlayingPause

class StateRecording < StateDefault
  include Singleton
  def play(ctx)
    stop(ctx).play(ctx)
  end
  def record(ctx)
    self
  end
  def pause(ctx)
    pause_recorder(ctx)
    StateRecordingPause.instance
  end
  def stop(ctx)
    stop_recorder(ctx)
    StateStopped.instance
  end
  def set_marker(ctx, *args)
    warn "TODO not yet implemented"
    #ctx.pos.slice.set_marker(ctx.pos.offset)
    self
  end
  def delete(ctx)
    stop(ctx).delete(ctx)
  end
  def reset(ctx)
    stop_recorder(ctx)
    super
  end
end # class StateRecording

class StateRecordingPause < StateDefault
  include Singleton
  def play(ctx)
    stop(ctx).play(ctx)
  end
  def record(ctx)
    resume_recorder(ctx)
    StateRecording.instance
  end
  def pause(ctx)
    self
  end
  def resume(ctx)
    resume_recorder(ctx)
    StateRecording.instance
  end
  def stop(ctx)
    stop_recorder(ctx)
    StateStopped.instance
  end
  def delete(ctx)
    stop(ctx).delete(ctx)
  end
  def reset(ctx)
    stop_recorder(ctx)
    super
  end
end # class StateRecordingPause

class StateStopped < StateDefault
  include Singleton
  def stop(ctx)
    return self
  end
  def load(ctx, slice_filename)
    new_slice = ASlice.new(slice_filename)
    new_slice.update_file_duration
    new_slice.duration = new_slice.file_duration
    # XXX >> redundant to run_recorder
    if ctx.pos.slice
      latched_offset = ctx.pos.slice.insert(ctx.pos.offset, new_slice)
      ctx.pos.timecode += latched_offset - ctx.pos.offset
    end
    ctx.pos.slice = new_slice
    ctx.pos.offset = 0
    dbg_dump_slices(ctx.pos.slice)
    # << XXX
    record_command(:load, slice_filename)
    return self
  end
end

