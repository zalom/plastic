# frozen_string_literal: true

# A small package of skills and agent role files in a throwaway home, and the
# real checkout as the package for the install tests.
module PackageFixture
  REAL_PACKAGE = File.expand_path("../../..", __dir__)
  ROLE = "---\nname: demo-role\ndescription: Demo \"role\"\nmodel: sonnet\n---\nBody of the role.\n"

  def write(path, text)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, text)
    path
  end

  def package(roles: { "demo-role" => ROLE }, skills: {})
    root = File.join(@home, "package")
    roles.each { |name, text| write(File.join(root, "agents", "#{name}.md"), text) }
    skills.each { |path, text| write(File.join(root, "skills", path), text) }
    write(File.join(root, "VERSION"), "2.0.3\n")
    root
  end

  def config_with(text)
    write(File.join(@plastic_home, "config.yml"), text)
  end
end
