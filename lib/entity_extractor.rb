# encoding: utf-8

class RTesseract
  def tiff_path(path)
    @path = path
  end
  # monkeypatch method to make use of the TIFF just made
  def image
    @path
  end
  # monkeypatch method so as not to delete TIFF before we're finished with it
  def convert_result
    convert_text
    RTesseract::Utils.remove_files([file_with_ext])
  end
end

class EntityExtractor
  attr_reader :source
  attr_accessor :options

  def initialize(src = '', options = {})
    self.source = src
    self.options = options
  end

  def source=(src)
    if src != '' && File.extname(src) != ".pdf"
      raise RuntimeError, 'File must be a PDF'
    end
    @page_text = []
    @source = src
  end

  def options=(options)
    @options = options
    if options[:yaml]
      yaml = YAML.load_file(options[:yaml])
                 .each_with_object({}){|(k,v), h| h[k.to_sym] = v}
    end
    @options.merge!(yaml)
  end

  def page_text
    raise RuntimeError, 'Source has not been set' if @source == ''
    return @page_text if !@page_text.empty?

    begin
      reader = PDF::Reader.new(@source)
      @page_text = reader.pages.map(&:text)
    rescue
      @page_text = ocr
    end
  end

  def entities
    first_page = page_text.first
    first_2_pages = page_text.first(2).join("\n")
    last_2_pages = page_text.last(2).join("\n")
    all_pages = page_text.join("\n")
    { doi: dois(first_2_pages).first,
      possible_authorship: contains_phrase?(first_page),
      possible_citation: contains_phrase?(last_2_pages),
      museum_codes: specimen_codes(all_pages),
      dois: dois(all_pages),
      orcids: orcids(all_pages),
      coordinates: coordinates(all_pages)
    }
  end

  def contains_phrase?(txt)
    if !@options[:search_phrase_regex]
      raise RuntimeError, 'Missing :search_phrase_regex in option'
    end
    !!txt.match(@options[:search_phrase_regex])
  end

  def specimen_codes(txt)
    if !@options[:specimen_codes_regex]
      raise RuntimeError, 'Missing :specimen_codes_regex in option'
    end
    txt.scan(@options[:specimen_codes_regex])
       .flatten.map{|o| o.strip.gsub(/\s+/, " ") }.uniq.sort
  end

  def orcids(txt)
    orcid_pattern = /\d{4}-\d{4}-\d{4}-\d{3}[0-9X]/
    txt.scan(orcid_pattern).flatten.uniq
  end

  def dois(txt)
    doi_pattern = /(10[.][0-9]{4,}(?:[.][0-9]+)*\/(?:(?![%"#? ])\S)+)/i
    txt.scan(doi_pattern).flatten.uniq
  end

  def coordinates(txt)
    #dd coordinates
    coords = []
    coord_pattern_dd = /([-+]?\d{1,2}[.]\d+)[d°º]?[NS]?,\s*([-+]?\d{1,3}[.]\d+)[d°º]?[EWO]?/
    coords << txt.scan(coord_pattern_dd)
                .map{|o| { lat: o[0].to_f, lng: o[1].to_f }}

    #dms coordinates
    coord_pattern_dms = /([0-9]{1,2})[d°º]([0-9]{1,2}(?:\.[0-9]+){0,1})?\s*?[m'′]?([0-9]{1,2}(?:\.[0-9]+){0,1})?[s"″]?\s*([NS]),\s*([0-9]{1,3})[d°º]([0-9]{1,2}(?:\.[0-9]+){0,1})?\s*?[m'′]?([0-9]{1,2}(?:\.[0-9]+){0,1})?[s"″]?\s*?([EWO])/
    coords << txt.scan(coord_pattern_dms)
                 .map{|o| convert_dms(o)}
    coords.uniq.flatten
  end

  private

  def convert_dms(o)
    lat_prefix = 1
    if o[3] == "S"
      lat_prefix = -1
    end
    lng_prefix = 1
    if o[7] == "W" || o[7] == "O"
      lng_prefix = -1
    end
    lat = lat_prefix * (o[0].to_f + o[1].to_f/60 + o[2].to_f/3600)
    lng = lng_prefix * (o[4].to_f + o[5].to_f/60 + o[6].to_f/3600)
    { lat: lat, lng:  lng }
  end

  def ocr
    doc = {}
    pdf = MiniMagick::Image.open(@source)
    Parallel.map(pdf.pages.each_with_index, in_threads: 8) do |page, idx|
      tmpfile = Tempfile.new(['', '.tif'])
      MiniMagick::Tool::Convert.new do |convert|
        convert.density(300)
        convert << page.path
        convert.alpha("off")
        convert << tmpfile.path
      end
      tess = RTesseract.new(tmpfile.path)
      tess.tiff_path tmpfile.path
      doc[idx] = tess.to_s
      tmpfile.unlink
    end
    doc.sort.to_h.values
  end

end