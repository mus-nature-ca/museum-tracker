describe "EntityExtractor" do
  subject { EntityExtractor }
  let(:ee) { subject.new('', { yaml: REGEX_FILE }) }

  describe ".new" do
    it "works" do
      expect(ee).to be_kind_of EntityExtractor
    end
  end

  describe ".museum_codes" do
    it "recognizes all known museum codes for the Canadian Museum of Nature" do
      ee.src = read("museum_codes.txt")
      expect(ee.museum_codes.count).to eq 62
    end
    it "does not recognize museum codes for the Canadian Museum of Nature when are lowercase" do
      ee.src = "Can the can 12345 and the cmn 0123 be recocognized?"
      expect(ee.museum_codes.count).to eq 0
    end
  end

  describe ".dois" do
    it "recognizes DOI in text" do
      ee.src = "10.1111/geb.12667"
      expect(ee.dois.first).to eq "10.1111/geb.12667"
    end
    it "recognizes DOI with https://doi.org in text" do
      ee.src = "https://doi.org/10.1111/geb.12667"
      expect(ee.dois.first).to eq "10.1111/geb.12667"
    end
    it "recognizes DOI with https://dx.doi.org in text" do
      ee.src = "https://dx.doi.org/10.1111/geb.12667"
      expect(ee.dois.first).to eq "10.1111/geb.12667"
    end
    it "recognized 2 DOIs in text" do
      ee.src = "This text contains two DOIs: http://doi.org/10.3342/12345/a12 and 10.4432/abc/123/12"
      expect(ee.dois).to eq ["10.3342/12345/a12", "10.4432/abc/123/12"]
    end
    it "does not find DOI when there is none to be had" do
      ee.src = "There are no DOIs here"
      expect(ee.dois).to eq []
    end
    it "recognized messy DOI in text" do
      ee.src = "10.1016/j.jaa.2018.05.004';"
      expect(ee.dois.first).to eq "10.1016/j.jaa.2018.05.004"
    end
  end

  describe ".orcids" do
    it "recognizes ORCID without the X terminator" do
      ee.src = "0000-1111-1111-8888"
      expect(ee.orcids.first).to eq "0000-1111-1111-8888"
    end
    it "recognizes ORCID with the X terminator" do
      ee.src = "0000-1111-1111-888X"
      expect(ee.orcids.first).to eq "0000-1111-1111-888X"
    end
    it "does not find an ORCID when there is none to be had" do
      ee.src = "This is some text with no ORCIDs present"
      expect(ee.orcids).to eq []
    end
  end

  describe ".coordinates" do
    it "recognized geographic coordinates as DMS without MS in text" do
      ee.src = "Rodadero Bay, Magdalena, northern Colombia (11°N, 74°W)."
      expect(ee.coordinates).to eq [{ lat: 11.0, lng: -74.0 }]
    end
    it "recognizes geographic coordinates as full DMS in text" do
      ee.src = "Fanar 33°52'44\"N, 35°34'04\"E"
      expect(ee.coordinates).to eq [{ lat: 33.87888888888889, lng: 35.56777777777778 }]
    end
    it "recognizes geographic coordinates as DM deg S in text" do
      ee.src = "Hasbaya 33°23'52.35\"N, 35°41.6'6.59\"W"
      expect(ee.coordinates).to eq [{ lat: 33.397875, lng: -35.69516388888889 }]
    end
    it "recognizes geographic coordinates as DD in text" do
      ee.src = "Rodadero Bay, Magdalena, northern Colombia (11.24, -74.20)."
      expect(ee.coordinates).to eq [{ lat: 11.24, lng: -74.20 }]
    end
    it "recognizes geographic coordinates as DD with symbols and direction" do
      ee.src = "Diaoluoshan, Xin-an, 18.72510°N, 109.86861°E, 921m"
      expect(ee.coordinates).to eq [{ lat: 18.7251, lng: 109.86861 }]
    end
    it "recognizes 2 geographic coordinates as DD and DMS in text" do
      ee.src = "Rodadero Bay, Magdalena, northern Colombia (11.24, -74.20) and Hasbaya 33°23'52.35\"N, 35°41.6'6.59\"W."
      expect(ee.coordinates).to eq [{ lat: 11.24, lng: -74.2 }, { lat: 33.397875, lng:-35.69516388888889 }]
    end
    it "does not recognize geographic coordinates as DD in text when there is just one number" do
      ee.src = "Rodadero Bay, Magdalena, northern Colombia 11.24 and elsewhere."
      expect(ee.coordinates).to eq []
    end
  end

  def read(file)
    File.read(File.join(__dir__, "files", file))
  end

end
