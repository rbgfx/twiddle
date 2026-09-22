# Twiddle

[![Gem version](https://badge.fury.io/rb/twiddle.svg)](https://rubygems.org/gems/twiddle)
[![Downloads](https://img.shields.io/gem/dt/twiddle?label=downloads)](https://rubygems.org/gems/twiddle)
[![CI](https://github.com/rbgfx/twiddle/actions/workflows/ci.yml/badge.svg)](https://github.com/rbgfx/twiddle/actions/workflows/ci.yml)
[![Ruby](https://img.shields.io/badge/ruby-%3E%3D3.1-CC342D?logo=ruby&logoColor=white)](https://www.ruby-lang.org/)
[![License](https://img.shields.io/badge/license-MIT-750014.svg)](LICENSE.txt)

> A headless-friendly immediate-mode UI toolkit for Ruby graphics.

Twiddle renders compact controls into Tessel images and accepts plain event
hashes, so the same UI can run in tests, a headless renderer, or an rbgl
window.

**[Features](#features) · [Installation](#installation) · [Quick start](#quick-start) · [RBGL integration](#rbgl-integration) · [Development](#development)**

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

## Quick start

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

## License

[MIT](LICENSE.txt)
