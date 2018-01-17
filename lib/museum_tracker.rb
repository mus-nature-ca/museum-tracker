# encoding: utf-8

SCI_HUB_URLS = [
  "https://sci-hub.la",
  "https://sci-hub.hk",
  "https://sci-hub.mn",
  "https://sci-hub.name",
  "https://sci-hub.tv",
  "https://sci-hub.tw",
  "https://tree.sci-hub.la"
]

SCI_HUB_ONION = "http://scihub22266oqcxt.onion"

class MuseumTracker

  def initialize args
    args.each do |k,v|
      instance_variable_set("@#{k}", v) unless v.nil?
    end
    @config = parse_config
    @db = Sequel.connect(
      adapter: @config[:adapter],
      user: @config[:username],
      host: @config[:host],
      database: @config[:database],
      password: @config[:password]
      )
  end

  def new_gmail_citations
    service = Google::Apis::GmailV1::GmailService.new
    service.client_options.application_name = @config[:gmail][:application_name]
    service.authorization = gmail_authorize

    labels = service.list_user_labels("me").labels
    scholar_id = labels.select{|label| label.name == @config[:gmail][:label]}.first.id
    message_ids = service.list_user_messages("me", { label_ids: ["#{scholar_id}"] })
                         .messages.collect(&:id) rescue []

    citations = []
    message_ids.each do |id|
      message = service.get_user_message("me", id)
      payload = message.payload
      body = payload.body.data
      if body.nil? && payload.parts.any?
        body = payload.parts.map{|part| part.body.data}.join
      end
      urls = extract_scholar_urls(body)
      urls.each do |url|
        url = extract_publisher_url(url)
        md5 = Digest::MD5.hexdigest(url)
        doi = extract_doi(url)
        created = Time.now.strftime('%Y-%m-%d %H:%M:%S')
        citations << { md5: md5, doi: doi, url: url, created: created }
      end
      if @delete_messages
        service.delete_user_message("me", id)
      end
    end

    citations.uniq! { |e| e[:url] }
    citations.map { |citation| @db[:citations].insert(citation) }
  end

  def insert_file(path, doi = nil)
    raise RuntimeError, 'File must be a PDF' if !valid_pdf(path)

    md5 = Digest::MD5.hexdigest(path)
    citation = {
      md5: md5,
      url: "/pdfs/#{md5}.pdf",
      doi: doi,
      status: 3,
      created:  Time.now.strftime('%Y-%m-%d %H:%M:%S')
    }
    FileUtils.cp(path, citation_pdf(citation))
    @db[:citations].insert(citation)
  end

  def insert_doi(doi)
    md5 = Digest::MD5.hexdigest(doi)
    citation = {
      md5: md5,
      url: "https://doi.org/" + URI.escape(doi),
      doi: doi,
      status: 1,
      created:  Time.now.strftime('%Y-%m-%d %H:%M:%S')
    }
    @db[:citations].insert(citation)
  end

  def queue_and_run
    hydra = Typhoeus::Hydra.hydra
    @db[:citations].where(status: 0).all.in_groups_of(5).each do |group|
      group.each do |citation|
        req = request(citation)
        hydra.queue req if !req.nil?
      end
      hydra.run
    end
  end

  def send_scihub_requests
    @db[:citations].where(status: 1).each do |citation|
      slug = !citation[:doi].nil? ? citation[:doi] : citation[:url]
      req = Typhoeus.get(active_scihub + "/#{slug}")
      doc = Nokogiri::HTML(req.body)
      url = doc.xpath("//*/iframe[@id='pdf']").first.attributes["src"].value rescue nil
      if url.nil?
        update_status(citation, 2)
      else
        second_req = Typhoeus.get("http:#{url}")
        pdf = citation_pdf(citation)
        File.open(pdf, 'wb') { |file| file.write(second_req.body) }
        if valid_pdf(pdf)
          update_status(citation, 3)
        else
          File.delete pdf
          update_status(citation, 2)
        end
      end
    end
  end

  def extract_entities
    yaml = File.join(root, 'regex.yml')
    ee = EntityExtractor.new("", { yaml: yaml })

    @db[:citations].where(status: 3).each do |citation|
      ee.source = citation_pdf(citation)
      citation[:possible_authorship] = ee.entities[:possible_authorship]
      citation[:possible_citation] = ee.entities[:possible_citation]
      specimens = ee.entities[:museum_codes]
      orcids = ee.entities[:orcids]

      if specimens.count > 0
        bulk = Array.new(specimens.count, citation[:id]).zip(specimens)
        @db[:specimens].import([:citation_id, :specimen_code], bulk)
      end

      if orcids.count > 0
        bulk = Array.new(orcids.count, citation[:id]).zip(orcids)
        @db[:orcids].import([:citation_id, :orcid], bulk)
      end

      if citation[:doi].nil? && !ee.entities[:doi].nil?
        citation[:doi] = ee.entities[:doi]
      end

      citation[:status] = 4
      @db[:citations].where(md5: citation[:md5]).update(citation)
    end
  end

  def update_metadata
    bibtex = []
    sql = "SELECT
      c.id, c.doi
    FROM citations c 
    LEFT JOIN metadata m ON c.id = m.citation_id 
    WHERE m.id IS NULL AND c.doi IS NOT NULL"
    @db[sql].each do |row|
      bib = doi_metadata(row[:doi], "bibtex")
      formatted = doi_metadata(row[:doi], "biblio")
      json = JSON.parse(doi_metadata(row[:doi], "csl+json")) rescue nil
      print_date = json["published-print"]["date-parts"][0].join("-") rescue nil
      if print_date.nil?
        print_date = json["published-online"]["date-parts"][0].join("-") rescue nil
      end
      year = BibTeX.parse(bib).first.year.to_i rescue nil
      if bib && formatted
        data = {
          citation_id: row[:id],
          year: year,
          print_date: print_date,
          bibtex: bib,
          formatted: formatted
        }
        @db[:metadata].insert(data)
        bibtex << data
      end
    end
    bibtex
  end

  def write_webpage
    output = {
      generation_time: Time.now.strftime('%Y-%m-%d %H:%M:%S'),
      entries: []
    }
    sql = "SELECT 
        c.id,
        c.doi,
        c.url,
        c.possible_authorship,
        c.possible_citation,
        m.formatted,
        m.print_date,
        c.created 
      FROM 
        citations c 
      LEFT JOIN 
        metadata m ON (c.id = m.citation_id) 
      ORDER BY m.print_date DESC"
    @db[sql].each do |row|
      extras = { 
        specimens: @db[:specimens].where(citation_id: row[:id])
                                  .all.map{ |s| s[:specimen_code] }.join(", "),
        orcids: @db[:orcids].where(citation_id: row[:id]).select_map(:orcid)
      }
      output[:entries] << row.merge(extras)
    end
    template = File.join(root, 'template', "template.slim")
    web_page = File.join(root, 'index.html')
    html = Slim::Template.new(template).render(Object.new, output)
    File.open(web_page, 'w') { |file| file.write(html) }
    html
  end

  private

  def root
    File.dirname(File.dirname(__FILE__))
  end

  def parse_config
    config = YAML.load_file(@config_file).deep_symbolize_keys!
    env = ENV.key?("ENVIRONMENT") ? ENV["ENVIRONMENT"] : "development"
    config[env.to_sym]
  end

  def doi_metadata(doi, style = 'biblio')
    url = "https://doi.org/" + URI.escape(doi)

    case style
    when 'biblio'
      header = { Accept: "text/x-bibliography" }
    when 'bibtex'
      header = { Accept: "application/x-bibtex" }
    when 'csl+json'
      header = { Accept: "application/vnd.citationstyles.csl+json" }
    else
      header = { Accept: "text/x-bibliography" }
    end

    begin
      req = Typhoeus.get(url, headers: header, followlocation: true)
      req.response_body
    rescue
      nil
    end
  end

  def valid_pdf(pdf)
    mime_type = `file --mime -b "#{pdf}"`.chomp
    mime_type.include?("application/pdf")
  end

  def update_status(citation, status)
    @db[:citations].where(md5: citation[:md5]).update(status: status)
  end

  def gmail_authorize
    credentials_file = File.join(root, '.credentials', 'gmail-ruby.yaml')
    client_secret_file = File.join(root, '.credentials', 'gmail-client-secret.json')
    FileUtils.mkdir_p(File.dirname(credentials_file))

    client_id = Google::Auth::ClientId.from_file(client_secret_file)
    token_store = Google::Auth::Stores::FileTokenStore.new(file: credentials_file)
    authorizer = Google::Auth::UserAuthorizer.new(client_id, Google::Apis::GmailV1::AUTH_SCOPE, token_store)
    user_id = 'default'
    credentials = authorizer.get_credentials(user_id)
    if credentials.nil?
      url = authorizer.get_authorization_url(base_url: 'urn:ietf:wg:oauth:2.0:oob')
      puts "Open the following URL in the browser and enter the " +
           "resulting code after authorization"
      puts url
      code = gets
      credentials = authorizer.get_and_store_credentials_from_code(user_id: user_id, code: code, base_url: 'urn:ietf:wg:oauth:2.0:oob')
    end
    credentials
  end

  def extract_scholar_urls(body)
    doc = Nokogiri::HTML(body)
    doc.xpath("//*/a").collect{|l| l['href']}
       .delete_if{|u| !u.include?("scholar_url") || u.include?("researchgate")}
  end

  def extract_doi(txt)
    doi = nil
    doi_pattern = /(10[.][0-9]{4,}(?:[.][0-9]+)*\/(?:(?![%"#? ])\S)+)/i
    strip_out = %r{
      \/full|
      \/abstract|
      \.pdf|
      \&type=printable
    }x
    match = txt.match(doi_pattern)
    if match
      doi = match.captures.first.gsub(strip_out, '')
    end
    doi
  end

  def extract_publisher_url(url)
    uri = Addressable::URI.parse(url)
    uri.query_values["url"]
  end

  def request(citation)
    pdf = citation_pdf(citation)
    url = citation[:url]
    downloaded_file = File.open pdf, 'wb'

    req = Typhoeus::Request.new(url, followlocation: true)
    req.on_body do |chunk|
      downloaded_file.write(chunk)
    end
    req.on_complete do |response|
      downloaded_file.close
      if valid_pdf(pdf)
        update_status(citation, 3)
      else
        File.delete pdf
        update_status(citation, 1)
      end
    end
    req
  end

  def citation_pdf(citation)
    File.join(root, 'pdfs', "#{citation[:md5]}.pdf")
  end

  def active_scihub
    active_url = nil
    SCI_HUB_URLS.each do |url|
      req = Typhoeus.head(url)
      if req.response_code == 200
        active_url = url
        break
      else
        next
      end
    end
    active_url = SCI_HUB_ONION if active_url.nil?
    active_url
  end

end