# frozen_string_literal: true

# Replaces one method for a fault-injection block, then restores its original
# lookup and visibility even when the block raises.
module MethodReplacement
  def with_replacement(receiver, name, replacement)
    singleton = receiver.singleton_class
    original = receiver.method(name)
    visibility = %i[public protected private].find { |kind| singleton.public_send("#{kind}_method_defined?", name, false) }
    singleton.define_method(name, &replacement)
    yield
  ensure
    restore_method(singleton, name, original, visibility)
  end

  private

  def restore_method(singleton, name, original, visibility)
    if original.owner == singleton
      singleton.define_method(name, original)
      singleton.send(visibility, name)
    else
      singleton.remove_method(name)
    end
  end
end
