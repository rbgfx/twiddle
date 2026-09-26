# frozen_string_literal: true

RSpec.describe Twiddle do
  it "has a version number" do
    expect(Twiddle::VERSION).not_to be nil
  end

  it "applies and updates theme colors" do
    ui = Twiddle::Context.new(theme: { window: "#010203" })
    ui.frame { |g| g.window("theme") { g.label("ready") } }
    expect(ui.draw_list.commands.first.last).to eq([1, 2, 3, 255])

    ui.theme(text: [1, 2, 3, 128])
    expect(ui.theme[:text]).to eq([1, 2, 3, 128])
    expect { ui.theme(unknown: [0, 0, 0]) }.to raise_error(ArgumentError, /unknown theme/)
  end

  it "returns a button click once" do
    ui = Twiddle::Context.new
    clicked = []
    ui.frame(events: [{ type: :mouse_move, x: 20, y: 40 }, { type: :mouse_press, x: 20, y: 40 }]) { |g| g.window("x") { clicked << g.button("go") } }
    ui.frame(events: [{ type: :mouse_release, x: 20, y: 40 }]) { |g| g.window("x") { clicked << g.button("go") } }

    expect(clicked).to eq([false, true])
  end

  it "uses deterministic IDs and keeps invisible suffixes" do
    stack = Twiddle::IdStack.new

    expect(stack.id("speed##one")).not_to eq(stack.id("speed##two"))
    expect(stack.id("speed")).not_to eq(stack.id("color"))
  end

  it "does not click after releasing outside a button" do
    ui = Twiddle::Context.new
    ui.frame(events: [{ type: :mouse_press, x: 5, y: 5 }]) { |g| expect(g.button("go")).to be(false) }
    ui.frame(events: [{ type: :mouse_release, x: 200, y: 200 }]) { |g| expect(g.button("go")).to be(false) }
  end

  it "keeps widget IDs separate across windows" do
    ui = Twiddle::Context.new
    clicks = []
    ui.frame(events: [{ type: :mouse_press, x: 20, y: 40 }]) do |g|
      g.window("first") { clicks << g.button("go") }
      g.window("second", x: 200) { clicks << g.button("go") }
    end
    ui.frame(events: [{ type: :mouse_release, x: 20, y: 40 }]) do |g|
      g.window("first") { clicks << g.button("go") }
      g.window("second", x: 200) { clicks << g.button("go") }
    end
    expect(clicks).to eq([false, false, true, false])
  end

  it "keeps integer slider values and invokes callbacks only on changes" do
    ui = Twiddle::Context.new
    changes = []
    ui.frame { |g| expect(g.slider("count", 5, 0..10) { |v| changes << v }).to eq(5) }
    expect(changes).to be_empty
    ui.frame(events: [{ type: :mouse_press, x: 100, y: 9 }]) do |g|
      expect(g.slider("count", 5, 0..10) { |v| changes << v }).to be_a(Integer)
    end
    expect(changes).to eq([6])
  end

  it "reads Cocoa scroll deltas and scales integer plots proportionally" do
    ui = Twiddle::Context.new
    ui.frame(events: [{ type: :scroll, dx: 2.5, dy: -3.0, modifiers: [:shift] }]) do |g|
      g.plot_lines("values", [0, 1, 2], width: 20, height: 20)
    end
    expect([ui.input.scroll_x, ui.input.scroll_y, ui.input.modifiers]).to eq([2.5, -3.0, [:shift]])
    lines = ui.draw_list.commands.select { |command| command.first == :line }
    expect(lines.first[4]).to eq(10.0)

    ui.frame do |g|
      g.plot_lines("bounded", [0, 10, 20], width: 20, height: 20, minimum: 0, maximum: 10)
    end
    expect(ui.draw_list.commands.last[4]).to eq(0.0)
    expect { ui.frame { |g| g.plot_lines("bad", [1, 0], minimum: 2, maximum: 1) } }.to raise_error(ArgumentError)
  end

  it "rasterizes fractional line endpoints without drifting past the target" do
    ui = Twiddle::Context.new
    ui.draw_list.line(0.2, 0.2, 0.4, 3.1, [255, 0, 0, 255])
    image = Tessel::Image.new(4, 4)
    ui.render(image)
    expect(image[0, 3]).to eq([255, 0, 0, 255])
  end

  it "edits radio, drag, color, and text values headlessly" do
    ui = Twiddle::Context.new
    selected = :a
    value = 2.0
    color = [10, 20, 30]
    text = "ab"
    ui.frame(events: [{ type: :mouse_press, x: 20, y: 40 }]) do |g|
      g.window("x") do
        selected = g.radio("B", selected, :b)
        value = g.drag("amount", value)
        color = g.color_edit("color", color)
        text = g.input_text("name", text)
      end
    end
    ui.frame(events: [{ type: :mouse_release, x: 20, y: 40 }]) do |g|
      g.window("x") do
        selected = g.radio("B", selected, :b)
        value = g.drag("amount", value)
        color = g.color_edit("color", color)
        text = g.input_text("name", text)
      end
    end
    expect(selected).to eq(:b)
    expect(value).to be_a(Float)
    expect(color).to eq([10, 20, 30])
    expect(text).to eq("ab")

    text_ui = Twiddle::Context.new
    text_ui.frame(events: [{ type: :mouse_press, x: 20, y: 40 }]) do |g|
      g.window("text") { text = g.input_text("name", text) }
    end
    text_ui.frame(events: [{ type: :key_press, key: :left }, { type: :key_press, char: "!" }]) do |g|
      g.window("text") { text = g.input_text("name", text) }
    end
    expect(text).to eq("a!b")
  end

  it "moves drags, restores ASCII keys, and validates colors" do
    ui = Twiddle::Context.new
    value = 2.0
    ui.frame(events: [{ type: :mouse_press, x: 18, y: 40 }]) do |g|
      g.window("drag") do
        value = g.drag("amount", value, speed: 0.2, range: 0.0..10.0)
        expect(g.wants_mouse?).to be(true)
      end
    end
    ui.frame(events: [{ type: :mouse_move, x: 68, y: 40 }]) do |g|
      g.window("drag") { value = g.drag("amount", value, speed: 0.2, range: 0.0..10.0) }
    end
    expect(value).to eq(10.0)

    text = ""
    input = Twiddle::Context.new
    input.frame(events: [{ type: :mouse_press, x: 20, y: 40 }]) do |g|
      g.window("text") { text = g.input_text("name", text) }
    end
    input.frame(events: [{ type: :key_press, key: :a, modifiers: [:shift] }]) do |g|
      g.window("text") do
        text = g.input_text("name", text)
        expect(g.wants_keyboard?).to be(true)
      end
    end
    expect(text).to eq("A")

    expect { input.frame { |g| g.color_edit("bad", [0, 0]) } }.to raise_error(ArgumentError)
  end

  it "moves windows and keeps same-line and collapsing layout state" do
    ui = Twiddle::Context.new
    ui.frame(events: [{ type: :mouse_press, x: 20, y: 20 }]) { |g| g.window("x") { g.label("title") } }
    ui.frame(events: [{ type: :mouse_move, x: 60, y: 50 }]) { |g| g.window("x") { g.label("title") } }
    expect(ui.draw_list.commands.first[1, 2]).to eq([50, 40])

    ui.frame do |g|
      g.window("layout") do
        g.button("a")
        g.same_line
        g.button("b")
      end
    end
    buttons = ui.draw_list.commands.select { |command| command.first == :fill_rect && command[3] == 100 && command[4] == 22 }
    expect(buttons.map { |command| command[1, 2] }).to eq([[18, 40], [128, 40]])

    open = true
    ui.frame(events: [{ type: :mouse_press, x: 20, y: 40 }]) do |g|
      g.window("collapse") { open = g.collapsing_header("Advanced", open: open) { g.label("body") } }
    end
    ui.frame(events: [{ type: :mouse_release, x: 20, y: 40 }]) do |g|
      g.window("collapse") { open = g.collapsing_header("Advanced", open: open) { g.label("body") } }
    end
    expect(open).to be(false)
  end

  it "brings a clicked window to the front" do
    ui = Twiddle::Context.new
    draw = lambda do |events|
      ui.frame(events: events) do |g|
        g.window("back", x: 10, y: 10, width: 120, height: 70) { g.label("back") }
        g.window("front", x: 80, y: 10, width: 120, height: 70) { g.label("front") }
      end
    end

    draw.call([])
    draw.call([{ type: :mouse_press, x: 20, y: 15 }])
    windows = ui.draw_list.commands.select { |command| command.first == :fill_rect && command[3] == 120 && command[4] == 70 }
    expect(windows.last[1]).to eq(10)
    draw.call([])
    windows = ui.draw_list.commands.select { |command| command.first == :fill_rect && command[3] == 120 && command[4] == 70 }
    expect(windows.last[1]).to eq(10)
  end

  it "keeps the front window in control when title bars overlap" do
    ui = Twiddle::Context.new
    draw = lambda do |events|
      ui.frame(events: events) do |g|
        g.window("back", x: 10, y: 10, width: 120, height: 70) { g.label("back") }
        g.window("front", x: 80, y: 10, width: 120, height: 70) { g.label("front") }
      end
    end

    draw.call([])
    draw.call([{ type: :mouse_press, x: 90, y: 15 }])
    windows = ui.draw_list.commands.select { |command| command.first == :fill_rect && command[3] == 120 && command[4] == 70 }
    expect(windows.map { |command| command[1] }).to eq([10, 80])
  end

  it "collapses a window from its title bar control" do
    ui = Twiddle::Context.new
    draw = lambda do |events|
      ui.frame(events: events) { |g| g.window("panel", width: 120) { g.label("body") } }
    end

    draw.call([])
    expect(ui.draw_list.commands.any? { |command| command[1] == "body" }).to be(true)
    draw.call([{ type: :mouse_press, x: 115, y: 15 }])
    expect(ui.draw_list.commands.any? { |command| command[1] == "body" }).to be(false)
    draw.call([])
    expect(ui.draw_list.commands.any? { |command| command[1] == "body" }).to be(false)
  end

  it "attaches to an rbgl-like window" do
    window = Struct.new(:width, :height, :events, :pixels) do
      def poll_events_raw = events
      def set_pixels(value) = self.pixels = value
    end.new(32, 24, [], nil)
    gui = Twiddle::RBGL.attach(window)
    gui.frame(events: []) { |g| g.window("x") { g.label("ready") } }
    image = gui.render_to

    expect(image.width).to eq(32)
    expect(window.pixels.bytesize).to eq(32 * 24 * 4)
  end

  it "shows tooltips only after the hover delay" do
    ui = Twiddle::Context.new
    draw_tooltip = lambda do |delta|
      ui.frame(events: [{ type: :mouse_move, x: 20, y: 40 }], delta_time: delta) do |g|
        g.window("x") do
          g.button("go")
          g.tooltip("details", delay: 0.5)
        end
      end
    end

    draw_tooltip.call(0.25)
    expect(ui.draw_list.commands.any? { |command| command.first == :text && command[1] == "details" }).to be(false)
    draw_tooltip.call(0.25)
    expect(ui.draw_list.commands.any? { |command| command.first == :text && command[1] == "details" }).to be(false)
    draw_tooltip.call(0.25)
    expect(ui.draw_list.commands.any? { |command| command.first == :text && command[1] == "details" }).to be(true)
    expect { ui.frame(delta_time: -1) {} }.to raise_error(ArgumentError)
    expect { ui.frame(delta_time: Float::NAN) {} }.to raise_error(ArgumentError)
    expect { ui.frame(delta_time: Float::INFINITY) {} }.to raise_error(ArgumentError)
    expect { ui.frame { |g| g.tooltip("details", delay: -1) } }.to raise_error(ArgumentError)
  end

  it "scrolls window content and clips it to the body" do
    ui = Twiddle::Context.new
    draw = lambda do |events = []|
      ui.frame(events: events) do |g|
        g.window("scroll", height: 60) { 4.times { |index| g.button("item #{index}") } }
      end
    end

    draw.call
    image = Tessel::Image.new(140, 100)
    ui.render(image)
    expect(image[20, 85]).to eq([0, 0, 0, 0])

    draw.call([{ type: :scroll, x: 20, y: 50, dy: -2 }])
    ui.render(image.clear([0, 0, 0, 0]))
    expect(image[20, 45]).to eq([62, 70, 90, 255])
    expect(image[20, 75]).to eq([0, 0, 0, 0])

    clicked = nil
    ui.frame(events: [{ type: :mouse_press, x: 20, y: 75 }]) do |g|
      g.window("scroll", height: 60) { clicked = g.button("outside") }
    end
    expect(clicked).to be(false)
  end

  it "can reject duplicate widget IDs in debug mode" do
    ui = Twiddle::Context.new(debug: true)
    expect do
      ui.frame { |g| g.window("x") { g.button("same"); g.button("same") } }
    end.to raise_error(Twiddle::Error, /duplicate widget id/)
  end

  it "scales rendering and input coordinates together" do
    ui = Twiddle::Context.new(scale: 2)
    clicked = []
    ui.frame(events: [{ type: :mouse_press, x: 40, y: 84 }]) do |g|
      clicked << g.window("scaled") { g.button("go") }
    end
    image = Tessel::Image.new(300, 200)
    ui.render(image)
    expect(image[20, 20]).to eq([54, 60, 78, 255])
    ui.frame(events: [{ type: :mouse_release, x: 40, y: 84 }]) { |g| clicked << g.window("scaled") { g.button("go") } }
    expect(clicked).to eq([false, true])
  end

  it "rejects an infinite UI scale" do
    expect { Twiddle::Context.new(scale: Float::INFINITY) }.to raise_error(ArgumentError, /finite/)
  end

  it "edits bounded numeric values through keyboard input" do
    ui = Twiddle::Context.new
    value = 1.0
    ui.frame(events: [{ type: :mouse_press, x: 20, y: 40 }]) { |g| g.window("number") { value = g.input_number("amount", value, range: 0.0..10.0) } }
    ui.frame(events: [{ type: :key_press, key: :backspace }, { type: :key_press, key: :backspace }, { type: :key_press, key: :backspace }, { type: :key_press, char: "7" }]) do |g|
      g.window("number") { value = g.input_number("amount", value, range: 0.0..10.0) }
    end
    expect(value).to eq(7.0)
  end

  it "opens numeric slider input with a control click" do
    ui = Twiddle::Context.new
    value = 1.0
    ui.frame(events: [{ type: :mouse_press, x: 20, y: 40, modifiers: [:control] }]) do |g|
      g.window("slider") { value = g.slider("amount", value, 0.0..10.0) }
    end
    ui.frame(events: [{ type: :key_press, key: :backspace }, { type: :key_press, key: :backspace }, { type: :key_press, key: :backspace }, { type: :key_press, char: "8" }]) do |g|
      g.window("slider") { value = g.slider("amount", value, 0.0..10.0) }
    end
    expect(value).to eq(8.0)
  end
end
