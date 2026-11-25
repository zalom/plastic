# frozen_string_literal: true

module Plastic
  module Installations
    # The words a role file takes from the settings at install time. A role
    # file names the worker limit as {{driver.max_workers}}; the installed copy
    # carries the number the owner set.
    module RoleText
      WORKERS = "{{driver.max_workers}}"

      module_function

      def fill(text, workers) = workers ? text.gsub(WORKERS, workers.to_s) : text
    end
  end
end
