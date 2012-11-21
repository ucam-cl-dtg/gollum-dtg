module Precious
  module Views
    class WikiList < Layout

      attr_reader :content, :page, :footer, :results, :query
      DATE_FORMAT = "%Y-%m-%d %H:%M:%S"
      DEFAULT_AUTHOR = 'you'
      
      def has_results
        !@results.empty?
      end

      def no_results
        @results.empty?
      end

      def guest_mode
        !@loggedin
      end
      
      def loggedin
        @loggedin
      end
      
      def username
        @username
      end

    end
  end
end
