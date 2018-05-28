describe "EntityExtractor" do
  subject { EntityExtractor }
  let(:ee) { subject.new('', { yaml: REGEX_FILE }) }

  describe ".new" do
    it "works" do
      expect(ee).to be_kind_of EntityExtractor
    end
  end

  describe ".specimen_codes" do
    it "recognizes all known museum codes for the Canadian Museum of Nature" do
      txt = read("museum_codes.txt")
      expect(ee.specimen_codes(txt).count).to eq 62
    end
    it "does not recognize museum codes for the Canadian Museum of Nature when are lowercase" do
      txt = "Can the can 12345 and the cmn 0123 be recocognized?"
      expect(ee.specimen_codes(txt).count).to eq 0
    end
  end

  describe ".dois" do
    it "recognizes DOI in text" do
      doi = "10.1111/geb.12667"
      expect(ee.dois(doi).first).to eq doi
    end
    it "recognizes DOI with https://doi.org in text" do
      doi = "https://doi.org/10.1111/geb.12667"
      expect(ee.dois(doi).first).to eq "10.1111/geb.12667"
    end
    it "recognizes DOI with https://dx.doi.org in text" do
      doi = "https://dx.doi.org/10.1111/geb.12667"
      expect(ee.dois(doi).first).to eq "10.1111/geb.12667"
    end
    it "recognized 2 DOIs in text" do
      doi = "This text contains two DOIs: http://doi.org/10.3342/12345/a12 and 10.4432/abc/123/12"
      expect(ee.dois(doi)).to eq ["10.3342/12345/a12", "10.4432/abc/123/12"]
    end
    it "does not find DOI when there is none to be had" do
      doi = "There are no DOIs here"
      expect(ee.dois(doi)).to eq []
    end
    it "recognized messy DOI in text" do
      doi = "10.1016/j.jaa.2018.05.004';"
      expect(ee.dois(doi).first).to eq "10.1016/j.jaa.2018.05.004"
    end
  end

  describe ".orcids" do
    it "recognizes ORCID without the X terminator" do
      orcid = "0000-1111-1111-8888"
      expect(ee.orcids(orcid).first).to eq orcid
    end
    it "recognizes ORCID with the X terminator" do
      orcid = "0000-1111-1111-888X"
      expect(ee.orcids(orcid).first).to eq orcid
    end
    it "does not find an ORCID when there is none to be had" do
      orcid = "This is some text with no ORCIDs present"
      expect(ee.orcids(orcid)).to eq []
    end
  end

  describe ".coordinates" do
    it "recognized geographic coordinates as DMS without MS in text" do
      txt = "Rodadero Bay, Magdalena, northern Colombia (11°N, 74°W)."
      expect(ee.coordinates(txt)).to eq [{ lat: 11.0, lng: -74.0 }]
    end
    it "recognizes geographic coordinates as full DMS in text" do
      txt = "Fanar 33°52'44\"N, 35°34'04\"E"
      expect(ee.coordinates(txt)).to eq [{ lat: 33.87888888888889, lng: 35.56777777777778 }]
    end
    it "recognizes geographic coordinates as DM deg S in text" do
      txt = "Hasbaya 33°23'52.35\"N, 35°41.6'6.59\"W"
      expect(ee.coordinates(txt)).to eq [{ lat: 33.397875, lng: -35.69516388888889 }]
    end
    it "recognizes geographic coordinates as DD in text" do
      txt = "Rodadero Bay, Magdalena, northern Colombia (11.24, -74.20)."
      expect(ee.coordinates(txt)).to eq [{ lat: 11.24, lng: -74.20 }]
    end
    it "recognizes geographic coordinates as DD with symbols and direction" do
      txt = "Diaoluoshan, Xin-an, 18.72510°N, 109.86861°E, 921m"
      expect(ee.coordinates(txt)).to eq [{ lat: 18.7251, lng: 109.86861 }]
    end
    it "recognizes 2 geographic coordinates as DD and DMS in text" do
      txt = "Rodadero Bay, Magdalena, northern Colombia (11.24, -74.20) and Hasbaya 33°23'52.35\"N, 35°41.6'6.59\"W."
      expect(ee.coordinates(txt)).to eq [{ lat: 11.24, lng: -74.2 }, { lat: 33.397875, lng:-35.69516388888889 }]
    end
    it "does not recognize geographic coordinates as DD in text when there is just one number" do
      txt = "Rodadero Bay, Magdalena, northern Colombia 11.24 and elsewhere."
      expect(ee.coordinates(txt)).to eq []
    end
  end

  def read(file)
    File.read(File.join(__dir__, "files", file))
  end

end
