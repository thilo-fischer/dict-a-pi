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

# Audio slice
class ASlice
  # file - filename of the audio file
  # offset - slice start as milliseconds after start of audio file
  # duration - duration of slice in milliseconds
  # markers - array of objects of class Marker
  attr_accessor :file, :offset, :duration, :markers
  # predecessor, successor - preceeding and succeeding audio slices (doubly linked list)
  attr_accessor :predecessor, :successor
  def initialize(file, offset = 0.0, duration = nil)
    @file = file
    @offset = offset
    @duration = duration
    @markers = []
    @predecessor = nil
    @successor = nil
  end # def initialize
  def insert(offset, slice)
    case offset
    when 0..LATCH_TOLERANCE
      @predecessor.successor = slice if @predecessor
      slice.predecessor = @predecessor
      slice.successor = self
      @predecessor = slice
    when LATCH_TOLERANCE..(duration-LATCH_TOLERANCE)
      split(offset)
      insert(offset, slice)
    when (duration-LATCH_TOLERANCE)..duration
      @successor.predecessor = slice if @successor
      slice.successor = @successor
      slice.predecessor = self
      @successor = slice
    else
      warn "invalid offset: #{offset}"
    end
  end # def insert
  # remove region from offset from (inclusive)
  # till offset to (exclusive) from recording
  def delete(from, to)
    if from < LATCH_TOLERANCE
      # delete from slice beginning till +to+
      if offset > @duration - LATCH_TOLERANCE
        # delete complete slice
        @predecessor.successor = @successor
        @successor.predecessor = @predecessor
      else
        @offset = to
      end
    elsif offset > @duration - LATCH_TOLERANCE
      # delete from +from+ till slice ending
      @duration += from
    else
      # delete from +from+ till +to+
      split(to)
      split(from)
      @successor = @successor.successor
      @successor.predecessor = self
    end
  end
  def split(offset)
    if offset < LATCH_TOLERANCE or offset > @duration - LATCH_TOLERANCE
      warn "invalid offset: #{offset}"
      return
    end
    tail = ASlice.new(@file, @offset + offset, @duration - offset)
    @duration = offset
    @successor.predecessor = tail if @successor
    tail.successor = @successor
    tail.predecessor = self
    @successor = tail
    m_parts = @markers.partition {|m| m.offset < offset}
    @markers = m_parts[0]
    tail.markers = m_parts[1].collect {|m| Marker.new(m.offset - offset) }
  end
  def set_marker(ctx, offset)
    offset = ctx.pos.offset
    case offset
    when 0..LATCH_TOLERANCE
      offset = 0
    when LATCH_TOLERANCE..(ctx.pos.slice.duration-LATCH_TOLERANCE)
      @successor.markers << Marker.new(0)
      return
    end
    m = Marker.new(offset)
    @markers << m
  end
  def find_marker(offset)
    result = {}
    return result if @markers.empty?
    geq_idx = @markers.find_index {|m| m.offset >= offset-LATCH_TOLERANCE}
    if geq_idx
      geq = @markers[geq_idx]
      if geq.offset >= offset-LATCH_TOLERANCE and geq.offset <= offset+LATCH_TOLERANCE
        result[:accurate] = geq
        result[:previous] = @markers[geq_idx - 1] if geq_idx - 1 >= 0
        result[:next    ] = @markers[geq_idx + 1] if geq_idx + 1 <  @markers.length
        return result
      #elsif geq.offset < offset
      #  raise "programming error" # => should never get here ...
      #  result[:previous] = geq
      #  result[:next    ] = @markers[geq_idx + 1] if geq_idx + 1 <  @markers.length
      #  return result
      elsif geq.offset > offset
        result[:previous] = @markers[geq_idx - 1] if geq_idx - 1 >= 0
        result[:next    ] = geq
        return result
      else
        raise "programming error"
      end
    else
      result[:previous] = @markes.first
    end
  end
  def update_duration
    `soxi '#{file}'`.lines.find {|l| l =~ /^Duration\s*:\s*(\d+):(\d\d):(\d\d).(\d+)/}
    @duration = (($1.to_i * 60 + $2.to_i) * 60 + $3.to_i) * 1000 + ($4 + "000")[0..2].to_i
  end
end # class ASlice

class Marker
  # offset - position of marker in milliseconds after start of audio slice
  attr_accessor :offset
  def initialize(offset)
    @offset = offset
  end
end # class Marker

class Position
  attr_accessor :timecode, :slice, :offset
  def initialize
    @timecode = 0
    @slice = nil
    @offset = nil
  end
  # timecode of beginning of current slice
  def slice_begin
    @timecode - @offset
  end
  # timecode of ending of current slice
  def slice_end
    slice_begin + @slice.duration
  end
  def go_slice_begin
    @offset = 0
    @timecode -= @offset
  end
  def go_slice_end
    go_slice_begin
    @offset = @slice.duration
    @timecode += @offset
  end
  ##
  # whether the current slice has a predecessor
  def prev_slice?
    @slice.predecessor
  end
  ##
  # whether the current slice has a successor
  def next_slice?
    @slice.successor
  end
  ##
  # set +self+ to refer to the beginning of the previous slice
  def go_prev_slice
    go_slice_begin
    @slice = @slice.predecessor
    @timecode -= @slice.duration
  end
  ##
  # set +self+ to refer to the beginning of the following slice
  def go_next_slice
    go_slice_begin
    @slice = @slice.successor
    @timecode += @slice.duration
  end
  def seek(target_timecode)
    while target_timecode != @timecode
      if target_timecode < slice_begin
        if prev_slice?
          go_prev_slice
        else
          go_slice_begin
          break
        end
      elsif target_timecode >= slice_end
        if next_slice?
          go_next_slice
        else
          go_slice_end
          break
        end
      else
        @offset = target_timecode - slice_begin
        @timecode = target_timecode
      end
    end
    @timecode
  end
  def seek_end(offset)
    go_next_slice while next_slice?
    while @slice.duration < offset
      offset -= @slice.duration
      if prev_slice?
        go_prev_slice
      else
        # +self+ now refers to the beginnig of the first slice
        return @timecode
      end
    end
    @offset = @slice.duration - offset
    @timecode += @offset
  end
end # class Position

