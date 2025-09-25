require "spec_helper"
require "phrasekit"

RSpec.describe PhraseKit do
  it "has a version number" do
    expect(PhraseKit::VERSION).not_to be nil
  end

  describe ".hello" do
    it "returns greeting from native extension" do
      expect(PhraseKit.hello).to eq("Hello from PhraseKit native extension!")
    end
  end
end
