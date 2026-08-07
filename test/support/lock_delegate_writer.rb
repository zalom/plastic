# Subprocess driver for test/lock_atomic_write_test.rb (AC2): lets the test
# run two genuinely concurrent OS processes against one delivery.lock. Not a
# test file itself and never loaded by the suite loader (Dir["test/*_test.rb"]).

require File.expand_path(ARGV[0])

intent_dir = ARGV[1]
owner = ARGV[2]
prefix = ARGV[3]
count = Integer(ARGV[4])

successes = 0
count.times do |i|
  ok = Lock.add_delegate(intent_dir, delegate: "#{prefix}-#{i}", session: owner,
                         harness: "test", agent: prefix)
  successes += 1 if ok
end

puts successes
exit(successes == count ? 0 : 1)
