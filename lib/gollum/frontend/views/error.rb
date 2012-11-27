module Precious
  module Views
    class Error < Layout
      attr_reader :message

      def title
        @title!=nil ? @title : "Oh noes!"
      end

    end
  end
end
