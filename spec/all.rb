require 'docker'
require 'pry'

build_path = File.expand_path File.join(File.dirname(__FILE__), '..')
image_tag = 'test_klevo/percona'

describe "image" do
  before(:all) do
    # Build the image
    @image = Docker::Image.build_from_dir build_path, t: image_tag
  end
  
  it "should expose the mysql tcp port" do
    # binding.pry
    expect(@image.json["Config"]["ExposedPorts"]).to include("3306/tcp")
  end

  after(:all) do
    # @image.remove
  end
end