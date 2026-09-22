# frozen_string_literal: true

require_relative "../twiddle"

module Twiddle
  module RBGL
    class Attachment
      attr_reader :ui

      def initialize(window, font: nil, scale: 1.0)
        @window = window
        @ui = Context.new(font: font, scale: scale)
      end

      def frame(events: @window.poll_events_raw)
        @ui.frame(events: events) { |context| yield context }
      end

      def render_to(image = nil)
        image ||= Tessel::Image.new(@window.width, @window.height)
        @ui.render(image)
        @window.set_pixels(image.bytes)
        image
      end
    end

    def self.attach(window, font: nil, scale: 1.0)
      Attachment.new(window, font: font, scale: scale)
    end
  end
end
