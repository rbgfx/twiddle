# frozen_string_literal: true

require "tessel"
require "glyphic"

require_relative "twiddle/version"

module Twiddle
  class Error < StandardError; end
  DEFAULT_THEME = {
    window: [32, 36, 48, 240], title: [54, 60, 78, 255], text: [235, 238, 245, 255],
    button: [62, 70, 90, 255], button_hover: [78, 92, 120, 255], slider: [90, 96, 110, 255],
    accent: [100, 180, 240, 255], input: [24, 28, 38, 255], progress: [90, 180, 120, 255],
    separator: [100, 105, 120, 255], tooltip: [20, 24, 32, 245], plot: [120, 200, 240, 255],
    progress_background: [60, 64, 75, 255]
  }.transform_values(&:freeze).freeze

  class Input
    attr_reader :x, :y, :scroll_x, :scroll_y, :chars, :modifiers, :keys_pressed
    attr_accessor :mouse_down, :mouse_pressed, :mouse_released

    def initialize
      reset
    end

    def update(events, scale: 1.0)
      @mouse_pressed = @mouse_released = false
      @scroll_x = @scroll_y = 0
      @chars = +""
      @keys_pressed = []
      events.each do |event|
        @modifiers = event[:modifiers] if event.key?(:modifiers)
        case event[:type].to_sym
        when :mouse_move then @x, @y = logical_point(event, scale)
        when :mouse_press then @x, @y = logical_point(event, scale); @mouse_down, @mouse_pressed = true, true
        when :mouse_release then @x, @y = logical_point(event, scale); @mouse_down, @mouse_released = false, true
        when :scroll then @scroll_x += event[:dx].to_f; @scroll_y += event[:dy].to_f
        when :key_press
          key = event[:key]&.to_s&.to_sym
          @keys_pressed << key if key
          @chars << event[:char].to_s if event[:char]
          @chars << ascii_for(key) if !event[:char] && ascii_for(key)
        when :blur then @mouse_down = false; @mouse_released = true
        end
      end
    end

    private

    def logical_point(event, scale)
      [event[:x].to_f / scale, event[:y].to_f / scale]
    end

    def reset
      @x = @y = 0
      @mouse_down = @mouse_pressed = @mouse_released = false
      @scroll_x = @scroll_y = 0
      @chars = +""
      @keys_pressed = []
      @modifiers = []
    end

    def ascii_for(key)
      return unless key

      name = key.to_s.downcase
      character = case name
                  when "space" then " "
                  when /\A[a-z0-9]\z/ then name
                  end
      return unless character

      Array(@modifiers).map(&:to_sym).include?(:shift) ? character.upcase : character
    end
  end

  class IdStack
    def initialize
      @stack = [0xcbf29ce484222325]
    end

    def push(value)
      @stack << hash(@stack.last, value.to_s)
    end

    def pop
      raise Error, "ID stack is empty" if @stack.length == 1
      @stack.pop
    end

    def id(label)
      hash(@stack.last, label.to_s)
    end

    private

    def hash(seed, value)
      value.each_byte.reduce(seed) { |result, byte| ((result ^ byte) * 0x100000001b3) & 0xffffffffffffffff }
    end
  end

  class DrawList
    attr_reader :commands

    def initialize
      clear
    end

    def clear
      @commands = []
    end

    def fill_rect(x, y, width, height, color) = @commands << [:fill_rect, x, y, width, height, color]
    def rect(x, y, width, height, color) = @commands << [:rect, x, y, width, height, color]
    def line(x1, y1, x2, y2, color) = @commands << [:line, x1, y1, x2, y2, color]
    def text(value, x, y, color) = @commands << [:text, value, x, y, color]
    def push_clip(x, y, width, height) = @commands << [:push_clip, x, y, width, height]
    def pop_clip = @commands << [:pop_clip]
  end

  class Context
    attr_reader :input, :draw_list

    def initialize(font: nil, scale: 1.0, debug: false, theme: {})
      @font = font || Glyphic.default
      @scale = Float(scale)
      raise ArgumentError, "scale must be positive" unless @scale.positive?
      @debug = debug
      @theme = DEFAULT_THEME.transform_values(&:dup)
      set_theme(theme)
      @input = Input.new
      @ids = IdStack.new
      @draw_list = DrawList.new
      @windows = {}
      @cursor = [0, 0]
      @hot = @active = nil
      @wants_mouse = @wants_keyboard = false
      @text_states = {}
      @drag_states = {}
      @headers = {}
      @focus = nil
      @window_drag = nil
      @last_y = nil
      @time = 0.0
      @hover_id = nil
      @hover_since = nil
      @used_ids = {}
      @window_order = []
      @window_ranges = []
      @window_interaction_allowed = true
    end

    def theme(values = nil, **overrides)
      changes = (values || {}).merge(overrides)
      return @theme.dup if changes.empty?

      set_theme(changes)
      self
    end

    def frame(events: [], delta_time: 1.0 / 60.0)
      delta_time = Float(delta_time)
      raise ArgumentError, "delta_time must be finite and non-negative" unless delta_time.finite? && !delta_time.negative?
      @time += delta_time
      @input.update(events, scale: @scale)
      @active = nil if events.any? { |event| event[:type].to_sym == :blur }
      @focus = nil if @input.mouse_pressed
      @draw_list.clear
      @cursor = [0, 0]
      @hot = nil
      @wants_mouse = @wants_keyboard = false
      @last_y = nil
      @used_ids.clear
      @window_ranges.clear
      yield self
      reorder_windows
      @active = nil if @input.mouse_released
      @window_drag = nil if @input.mouse_released
      @hover_id = @hover_since = nil unless @hot == @hover_id
      self
    end

    def window(title, x: 10, y: 10, width: 240, height: 200)
      state = (@windows[title] ||= { x: x, y: y, width: width, height: height, cursor: 0, scroll_y: 0, content_height: 0 })
      @window_order << state unless @window_order.include?(state)
      command_start = @draw_list.commands.length
      title_hit = point_in_rect?(@input.x, @input.y, [state[:x], state[:y], state[:width], 22])
      collapse_hit = point_in_rect?(@input.x, @input.y, [state[:x] + state[:width] - 18, state[:y], 18, 22])
      @wants_mouse = true if title_hit
      if @window_drag == state && (@input.mouse_down || @input.mouse_released)
        state[:x] = @input.x - state[:drag_offset_x]
        state[:y] = @input.y - state[:drag_offset_y]
      end
      top_at_point = @window_order.reverse.find do |candidate|
        point_in_rect?(@input.x, @input.y, [candidate[:x], candidate[:y], candidate[:width], candidate[:height]])
      end
      if @input.mouse_pressed && top_at_point.equal?(state)
        @window_order.delete(state)
        @window_order << state
        if collapse_hit
          state[:collapsed] = !state[:collapsed]
        elsif title_hit && @window_drag.nil?
          @window_drag = state
          state[:drag_offset_x] = @input.x - state[:x]
          state[:drag_offset_y] = @input.y - state[:y]
        end
      end
      previous_window_interaction = @window_interaction_allowed
      @window_interaction_allowed = top_at_point.nil? || top_at_point.equal?(state)
      body_height = state[:collapsed] ? 0 : [state[:height] - 22, 0].max
      body = [state[:x], state[:y] + 22, state[:width], body_height]
      if @input.scroll_y != 0 && point_in_rect?(@input.x, @input.y, body)
        max_scroll = [state[:content_height] - body_height, 0].max
        state[:scroll_y] = [[state[:scroll_y] - @input.scroll_y * 20, 0].max, max_scroll].min
      end
      @draw_list.fill_rect(state[:x], state[:y], state[:width], state[:height], color(:window))
      @draw_list.fill_rect(state[:x], state[:y], state[:width], 22, color(:title))
      text(title, state[:x] + 8, state[:y] + 5)
      text(state[:collapsed] ? "+" : "-", state[:x] + state[:width] - 14, state[:y] + 5)
      previous = @cursor
      previous_last_y = @last_y
      previous_window = @window
      previous_interaction_clip = @interaction_clip
      @cursor = [state[:x] + 8, state[:y] + 30]
      @cursor[1] -= state[:scroll_y]
      @last_y = nil
      @window = state
      @interaction_clip = body
      @ids.push(title)
      @draw_list.push_clip(*body)
      pushed_clip = true
      yield self unless state[:collapsed]
    ensure
      @draw_list.pop_clip if pushed_clip
      state[:content_height] = [@cursor[1] + state[:scroll_y] - body[1], 0].max if state && @cursor && body
      state[:scroll_y] = [[state[:scroll_y], 0].max, [state[:content_height] - body[3], 0].max].min if state && body
      @ids.pop if pushed_clip
      if command_start
        @window_ranges << [state, @draw_list.commands.slice!(command_start, @draw_list.commands.length - command_start)]
      end
      @window_interaction_allowed = previous_window_interaction if defined?(previous_window_interaction)
      @cursor = previous if previous
      @last_y = previous_last_y if defined?(previous_last_y)
      @window = previous_window if defined?(previous_window)
      @interaction_clip = previous_interaction_clip if defined?(previous_interaction_clip)
    end

    def label(value)
      text(value, @cursor[0], @cursor[1])
      advance
      nil
    end

    def push_id(value) = @ids.push(value)
    def pop_id = @ids.pop

    def button(label, width: 100, height: 22)
      id = @ids.id(label)
      claim_id(id)
      x, y = @cursor
      hovered = hit?(x, y, width, height)
      mark_hover(id) if hovered
      @active = id if hovered && @input.mouse_pressed
      clicked = @active == id && @input.mouse_released && hovered
      @draw_list.fill_rect(x, y, width, height, hovered ? color(:button_hover) : color(:button))
      text(label.split("##", 2).first, x + 6, y + 5)
      advance(height)
      clicked
    end

    def checkbox(label, value)
      changed = button("[#{value ? "x" : " "}] #{label}##checkbox", width: 150)
      value = !value if changed
      yield(value) if changed && block_given?
      value
    end

    def collapsing_header(label, open: true)
      id = @ids.id("#{label}##header")
      current = @headers.fetch(id, open)
      if button("#{current ? "v" : ">"} #{label}##header", width: 200)
        current = !current
        @headers[id] = current
      end
      yield self if current && block_given?
      current
    end

    def radio(label, selected, value)
      changed = button("#{selected == value ? "(*)" : "( )"} #{label}##radio-#{value}", width: 150)
      selected = value if changed
      yield(selected) if changed && block_given?
      selected
    end

    def slider(label, value, range, width: 160)
      minimum, maximum = range.begin.to_f, range.end.to_f
      raise ArgumentError, "slider range must increase" unless maximum > minimum
      original = value
      integer = value.is_a?(Integer)
      id = @ids.id(label)
      claim_id(id)
      x, y = @cursor
      hovered = hit?(x, y, width, 18)
      mark_hover(id) if hovered
      numeric_label = "#{label}##number"
      direct_input = @focus == @ids.id(numeric_label) || hovered && @input.mouse_pressed && Array(@input.modifiers).map(&:to_sym).any? { |modifier| %i[control command].include?(modifier) }
      if direct_input
        return input_number(numeric_label, value, range: range, width: width) { |changed| yield(changed) if block_given? }
      end
      if hovered && @input.mouse_pressed
        @active = id
      end
      if @active == id && @input.mouse_down
        value = minimum + [[@input.x - x, 0].max, width].min.to_f / width * (maximum - minimum)
      end
      value = [[value.to_f, minimum].max, maximum].min
      value = value.round if integer
      @draw_list.fill_rect(x, y + 7, width, 4, color(:slider))
      @draw_list.fill_rect(x, y + 7, ((value - minimum) / (maximum - minimum) * width).round, 4, color(:accent))
      text("#{label}: #{value.round(3)}", x, y - 12)
      advance(24)
      yield(value) if block_given? && value != original
      value
    end

    def input_number(label, value, range:, step: nil, width: 180)
      original = value
      raise ArgumentError, "numeric input range must increase" unless range.end > range.begin
      raise ArgumentError, "numeric input step must be positive" if step && step.to_f <= 0
      raw = input_text(label, value, width: width)
      parsed = Float(raw)
      raise ArgumentError unless parsed.finite?
      parsed = (parsed / step).round * step if step
      parsed = [[parsed, range.begin.to_f].max, range.end.to_f].min
      parsed = parsed.round if value.is_a?(Integer)
      yield(parsed) if block_given? && parsed != original
      parsed
    rescue ArgumentError
      original
    end

    def drag(label, value, speed: 1.0, range: nil, width: 160)
      id = @ids.id(label)
      claim_id(id)
      x, y = @cursor
      state = (@drag_states[id] ||= {})
      hovered = hit?(x, y, width, 18)
      mark_hover(id) if hovered
      if hovered && @input.mouse_pressed
        @active = id
        state[:start_x] = @input.x
        state[:start_value] = value.to_f
      end
      if @active == id && @input.mouse_down
        value = state[:start_value] + (@input.x - state[:start_x]) * speed.to_f
      end
      if range
        value = [[value.to_f, range.begin.to_f].max, range.end.to_f].min
      end
      text("#{label}: #{value.round(3)}", x, y)
      advance(24)
      yield(value) if block_given? && value != state.fetch(:last_value, value)
      state[:last_value] = value
      value
    end

    def color_edit(label, value, alpha: value.length == 4, width: 160)
      expected = alpha ? 4 : 3
      raise ArgumentError, "color must have #{expected} channels" unless value.length == expected
      channels = value.dup
      names = alpha ? %w[R G B A] : %w[R G B]
      names.each_with_index do |name, index|
        channels[index] = slider("#{label} #{name}##{label}-#{name}", channels[index], 0..255, width: width)
      end
      channels
    end

    def input_text(label, value, width: 180)
      id = @ids.id(label)
      claim_id(id)
      x, y = @cursor
      state = (@text_states[id] ||= { value: value.to_s.dup, cursor: value.to_s.length })
      state[:value] = value.to_s.dup unless @focus == id || state[:value] == value.to_s
      state[:cursor] = [[state[:cursor], state[:value].length].min, 0].max
      hovered = hit?(x, y, width, 22)
      mark_hover(id) if hovered
      if hovered && @input.mouse_pressed
        @focus = id
        state[:cursor] = state[:value].length
      end
      if @focus == id
        @wants_keyboard = true
        @input.keys_pressed.each do |key|
          case key
          when :left then state[:cursor] = [state[:cursor] - 1, 0].max
          when :right then state[:cursor] = [state[:cursor] + 1, state[:value].length].min
          when :home then state[:cursor] = 0
          when :end then state[:cursor] = state[:value].length
          when :backspace
            if state[:cursor] > 0
              state[:value].slice!(state[:cursor] - 1)
              state[:cursor] -= 1
            end
          when :delete then state[:value].slice!(state[:cursor]) if state[:cursor] < state[:value].length
          end
        end
        @input.chars.each_char do |character|
          next if character.ord < 32
          state[:value].insert(state[:cursor], character)
          state[:cursor] += character.length
        end
      end
      @draw_list.fill_rect(x, y, width, 22, color(:input))
      text(state[:value], x + 4, y + 5)
      @draw_list.line(x + 4 + state[:cursor] * 6, y + 4, x + 4 + state[:cursor] * 6, y + 19, color(:text)) if @focus == id
      advance(26)
      yield(state[:value]) if block_given? && state[:value] != value.to_s
      state[:value]
    end

    def progress_bar(value, width: 160)
      value = [[value.to_f, 0].max, 1].min
      x, y = @cursor
      @draw_list.fill_rect(x, y, width, 8, color(:progress_background))
      @draw_list.fill_rect(x, y, (width * value).round, 8, color(:progress))
      advance(16)
    end

    def separator
      x, y = @cursor
      @draw_list.line(x, y, x + 200, y, color(:separator))
      advance(8)
    end

    def tooltip(value, delay: 0.5)
      delay = Float(delay)
      raise ArgumentError, "tooltip delay must not be negative" if delay.negative?
      return false unless @hot && @hover_id == @hot && @time - @hover_since >= delay

      x = @input.x + 8
      y = @input.y + 8
      width = value.to_s.length * 6 + 12
      @draw_list.fill_rect(x, y, width, 20, color(:tooltip))
      @draw_list.text(value, x + 6, y + 4, color(:text))
      true
    end

    def same_line(x = nil)
      @cursor[1] = @last_y if @last_y
      @cursor[0] = x || @cursor[0] + 110
    end

    def spacing(amount = 8)
      advance(amount)
    end

    def indent(amount = 20)
      @cursor[0] += amount
    end

    def unindent(amount = 20)
      @cursor[0] -= amount
    end

    def plot_lines(_label, values, height: 40, width: 160, minimum: nil, maximum: nil)
      return advance(height) if values.empty?
      x, y = @cursor
      minimum ||= values.min
      maximum ||= values.max
      raise ArgumentError, "plot range must not descend" if maximum < minimum
      span = [maximum - minimum, 1].max
      values.each_cons(2).with_index do |(left, right), index|
        x1 = x + index * width / [values.length - 1, 1].max
        x2 = x + (index + 1) * width / [values.length - 1, 1].max
        left_ratio = [[(left - minimum).to_f / span, 0].max, 1].min
        right_ratio = [[(right - minimum).to_f / span, 0].max, 1].min
        y1 = y + height - left_ratio * height
        y2 = y + height - right_ratio * height
        @draw_list.line(x1, y1, x2, y2, color(:plot))
      end
      advance(height)
    end

    def render(image)
      if @scale != 1.0
        logical = Tessel::Image.new((image.width / @scale).ceil, (image.height / @scale).ceil)
        render_commands(logical)
        image.blit(logical.scale_nearest(image.width, image.height), 0, 0, blend: :alpha)
        return image
      end
      render_commands(image)
    end

    def render_commands(image)
      clips = []
      clip = nil
      @draw_list.commands.each do |command|
        case command[0]
        when :fill_rect then fill(image, *command[1, 4], command[5], clip)
        when :rect
          x, y, width, height, color = command[1..]
          fill(image, x, y, width, 1, color, clip)
          fill(image, x, y + height - 1, width, 1, color, clip)
          fill(image, x, y, 1, height, color, clip)
          fill(image, x + width - 1, y, 1, height, color, clip)
        when :line
          x1, y1, x2, y2, color = command[1..]
          x1, y1, x2, y2 = [x1, y1, x2, y2].map(&:round)
          dx = (x2 - x1).abs
          dy = -(y2 - y1).abs
          sx = x1 < x2 ? 1 : -1
          sy = y1 < y2 ? 1 : -1
          error = dx + dy
          loop do
            image[x1, y1] = color if point_in_rect?(x1, y1, clip)
            break if x1 == x2 && y1 == y2
            twice = error * 2
            if twice >= dy then error += dy; x1 += sx end
            if twice <= dx then error += dx; y1 += sy end
          end
        when :text
          draw_text(image, command[1], command[2], command[3], command[4], clip)
        when :push_clip
          clip = intersect_clip(clip, command[1, 4])
          clips << clip
        when :pop_clip
          clip = clips.pop
        end
      end
      image
    end

    def wants_mouse? = @wants_mouse || !@active.nil? || !@hot.nil?
    def wants_keyboard? = @wants_keyboard

    private

    def text(value, x, y)
      @draw_list.text(value.to_s, x, y, color(:text))
    end

    def fill(image, x, y, width, height, color, clip)
      rectangle = clipped([x, y, width, height], clip)
      return unless rectangle

      image.fill_rect(*rectangle, color, blend: color.is_a?(String) ? :copy : :alpha)
    end

    def draw_text(image, value, x, y, color, clip)
      return unless @font
      return @font.draw(image, x, y, value, color: color) unless clip

      layer = Tessel::Image.new(image.width, image.height)
      @font.draw(layer, x, y, value, color: color)
      rectangle = clipped([clip[0], clip[1], clip[2], clip[3]], [0, 0, image.width, image.height])
      image.blit(layer, rectangle[0], rectangle[1], sx: rectangle[0], sy: rectangle[1], w: rectangle[2], h: rectangle[3], blend: :alpha) if rectangle
    end

    def advance(amount = 24)
      @last_y = @cursor[1]
      @cursor[1] += amount
    end

    def hit?(x, y, width, height)
      @window_interaction_allowed && @input.x >= x && @input.x < x + width && @input.y >= y && @input.y < y + height && point_in_rect?(@input.x, @input.y, @interaction_clip)
    end

    def reorder_windows
      ranges = @window_ranges.to_h { |state, commands| [state.object_id, commands] }
      @window_order.each { |state| @draw_list.commands.concat(ranges[state.object_id] || []) }
      @window_ranges.clear
    end

    def point_in_rect?(x, y, rectangle)
      return true unless rectangle

      x >= rectangle[0] && x < rectangle[0] + rectangle[2] && y >= rectangle[1] && y < rectangle[1] + rectangle[3]
    end

    def clipped(rectangle, clip)
      return rectangle unless clip

      x, y, width, height = rectangle
      x0 = [x.ceil, clip[0]].max
      y0 = [y.ceil, clip[1]].max
      x1 = [(x + width).floor, clip[0] + clip[2]].min
      y1 = [(y + height).floor, clip[1] + clip[3]].min
      x0 < x1 && y0 < y1 ? [x0, y0, x1 - x0, y1 - y0] : nil
    end

    def intersect_clip(left, right)
      return right unless left

      clipped(right, left) || [0, 0, 0, 0]
    end

    def mark_hover(id)
      if @hover_id != id
        @hover_id = id
        @hover_since = @time
      end
      @hot = id
    end

    def claim_id(id)
      return unless @debug
      raise Error, "duplicate widget id: #{id}" if @used_ids.key?(id)

      @used_ids[id] = true
    end

    def set_theme(values)
      raise TypeError, "theme must be a Hash" unless values.respond_to?(:each_pair)

      values.each_pair do |key, value|
        key = key.to_sym
        raise ArgumentError, "unknown theme color: #{key}" unless DEFAULT_THEME.key?(key)

        @theme[key] = Tessel::Color.pack(value).bytes.freeze
      end
    end

    def color(key)
      @theme.fetch(key)
    end
  end
end
