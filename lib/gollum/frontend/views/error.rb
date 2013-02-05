module Precious
  module Views
    class Error < Layout
      attr_reader :message

      def title
        @title!=nil ? @title : "Wicked. Tricksy, False."
      end

    end
  end
end
