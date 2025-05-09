# spec/imgup_cli/uploader_spec.rb
require "spec_helper"

RSpec.describe ImgupCli::Uploader do
  let(:uploader) { described_class.allocate }

  describe "#build_result" do
    it "formats all snippet types correctly" do
      url = "https://example.com/foo.jpg"
      # Use instance_exec to call private method
      result = uploader.send(:build_result, url)

      expect(result[:url]).to      eq(url)
      expect(result[:markdown]).to eq("![foo](#{url})")
      expect(result[:html]).to     eq("<img src=\"#{url}\" alt=\"foo\" />")
      expect(result[:org]).to      eq("[[img:#{url}][foo]]")
    end
  end
end
