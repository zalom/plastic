# frozen_string_literal: true

# The roadmap r1 that the tests of two homes change, and the reads of its rows.
module TwoHomesRoadmapHelper
  include TwoHomesHelper

  FILE = "roadmaps/r1.md"

  def seed(home)
    call_in(home, "roadmap", "new", "r1", "--title", "Road", "--goal", "A goal")
    call_in(home, "roadmap", "batch", "r1", "1", "--title", "First", "--goal", "g", "--done", "d")
  end

  def logs(home) = rows_of(home, :work, "SELECT text FROM roadmap_log ORDER BY position").map { |row| row["text"] }

  def goal(home) = rows_of(home, :work, "SELECT goal FROM roadmaps WHERE slug = 'r1'").first["goal"]

  def put_log(home, row) = database_of(home, :work).transaction { |batch| batch.put(:roadmap_log, { roadmap: "r1", at: Plastic::TestCase::STAMP, session_id: "s-1" }.merge(row)) }

  def to_both_homes(&) = two_homes(seed: method(:seed), &)

  def said(call) = call.out + call.err
end
