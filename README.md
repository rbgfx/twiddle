<h1 align="center">Twiddle</h1>

<p align="center">A headless-friendly immediate-mode UI toolkit for Ruby graphics.</p>

<p align="center">
  <a href="https://rubygems.org/gems/twiddle"><img src="https://badge.fury.io/rb/twiddle.svg" alt="Gem Version"></a>
  <a href="https://rubygems.org/gems/twiddle"><img src="https://img.shields.io/gem/dt/twiddle?label=downloads" alt="Downloads"></a>
  <a href="https://www.ruby-lang.org/"><img src="https://img.shields.io/badge/ruby-%3E%3D3.1-CC342D?logo=ruby&amp;logoColor=white" alt="Ruby Version"></a>
  <a href="LICENSE.txt"><img src="https://img.shields.io/badge/license-MIT-750014.svg" alt="License"></a>
</p>

[Features](#features) · [Installation](#installation) · [Quick Start](#quick-start) · [RBGL Integration](#rbgl-integration)

***

Twiddle renders compact controls into Tessel images and accepts plain event hashes, so the same UI can run in tests, a headless renderer, or an RBGL window.

## Features

- Buttons, checkboxes, radios, sliders, drags, text fields, and color editors.
- Progress bars, plots, collapsing headers, tooltips, and scrolling windows.
- Deterministic widget IDs with duplicate detection in debug mode.
- Logical coordinates with configurable rendering and input scale.
- Keyboard text input, mouse events, wheel scrolling, and modifier keys.
- Pure image rendering with an optional RBGL event and presentation adapter.

## Installation

Add Twiddle to your Gemfile:

~~~ruby
gem "twiddle"
~~~

Then run:

~~~sh
bundle install
~~~

Or install the released gem:

~~~sh
gem install twiddle
~~~

### Requirements

- Ruby 3.1 or newer.
- Tessel and Glyphic are installed as runtime dependencies; RBGL integration is optional.

## Quick Start

~~~ruby
require "tessel"
require "twiddle"

image = Tessel::Image.new(480, 320, fill: "#101827")
ui = Twiddle::Context.new

ui.frame(events: []) do |g|
  g.window("Parameters") do
    g.slider("speed", 1.0, 0.0..4.0)
  end
end

ui.render(image)
image.write("ui.png")
~~~

Pass <code>delta_time:</code> to <code>frame</code> for tooltip timing and
provide raw events with types such as <code>:mouse_press</code>,
<code>:mouse_move</code>, <code>:scroll</code>, and <code>:key_press</code>.

## RBGL integration

Load the adapter and attach Twiddle to an RBGL window:

~~~ruby
require "twiddle/rbgl"

Twiddle::RBGL.attach(window)
~~~

The adapter polls backend events and presents the rendered Tessel image with
<code>set_pixels</code>.

## Development

~~~sh
bundle install
bundle exec rake verify
~~~

## Contributing

Bug reports and pull requests are welcome at [rbgfx/twiddle](https://github.com/rbgfx/twiddle).

## License

[MIT](LICENSE.txt)
