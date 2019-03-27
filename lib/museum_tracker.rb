# encoding: utf-8

UNPAYWALL_URL = "http://api.unpaywall.org/v2/"

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

  def database
    @db
  end

  def citations
    @db[:citations]
  end

  def specimens
    @db[:specimens]
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
        citations << { md5: md5, url: url, doi: doi, status: 0, license: nil, created: created }
      end
      if @delete_messages
        service.delete_user_message("me", id)
      end
    end

    citations.uniq! { |e| e[:url] }
    citations.map { |citation| insert_citation(citation) }
  end

  def insert_file(path, doi = nil)
    raise RuntimeError, 'File must be a PDF' if !valid_pdf(path)

    md5 = Digest::MD5.hexdigest(path)
    citation = {
      md5: md5,
      url: nil,
      doi: doi,
      status: 3,
      license: nil,
      created:  Time.now.strftime('%Y-%m-%d %H:%M:%S')
    }
    FileUtils.cp(path, citation_pdf(citation))
    insert_citation(citation)
  end

  def insert_url(url, doi = nil)
    md5 = Digest::MD5.hexdigest(url)
    citation = {
      md5: md5,
      url: url,
      doi: doi,
      status: 0,
      license: nil,
      created: Time.now.strftime('%Y-%m-%d %H:%M:%S')
    }
    insert_citation(citation)
  end

  def insert_doi(doi)
    md5 = Digest::MD5.hexdigest(doi)
    citation = {
      md5: md5,
      url: "https://doi.org/" + URI.escape(doi),
      doi: doi,
      status: 1,
      license: nil,
      created:  Time.now.strftime('%Y-%m-%d %H:%M:%S')
    }
    insert_citation(citation)
  end

  def queue_and_run
    hydra = Typhoeus::Hydra.hydra
    citations.where(status: 0).all.in_groups_of(5, false).each do |group|
      group.each do |citation|
        req = queued_request(citation)
        hydra.queue req if !req.nil?
      end
      hydra.run
    end
  end

  #TODO: get ORCID data from unpaywall as well
  def send_unpaywall_requests
    citations.where(status: 1).exclude(doi: nil).each do |citation|
      url = UNPAYWALL_URL + citation[:doi] + "?email=#{@config[:gmail][:email_address]}"
      req = Typhoeus.get(url)
      json = JSON.parse(req.response_body, symbolize_names: true)
      pdf_url = json[:oa_locations].map{|o| o[:url_for_pdf]}.compact.first rescue nil
      citation[:license] = json[:best_oa_location][:license] rescue nil
      if pdf_url.nil?
        citation[:status] = 2
        update_citation(citation)
      else
        single_request(citation, pdf_url)
      end
    end
  end

  def single_request(citation, url)
    req = Typhoeus.get(url)
    pdf = citation_pdf(citation)
    File.open(pdf, 'wb') { |file| file.write(req.body) }
    if valid_pdf(pdf)
      citation[:status] = 3
      update_citation(citation)
    else
      File.delete pdf
      citation[:status] = 2
      update_citation(citation)
    end
  end

  def send_crossref_requests
    citations.where(status: [1,2]).exclude(doi: nil).each do |citation|
      begin
        work = Serrano.works(ids: citation[:doi]).first
        work["message"]["link"].each do |url|
          if url["content-type"] == "application/pdf"
            single_request(citation, url["URL"])
            break
          end
        end
      rescue
      end
    end
  end

  def extract_entities
    yaml = File.join(root, 'regex.yml')
    ee = EntityExtractor.new("", { yaml: yaml })

    citations.where(status: 3).each do |citation|
      ee.src = citation_pdf(citation)
      citation[:possible_authorship] = ee.authored?
      citation[:possible_citation] = ee.cited?
      entities = ee.entities
      found_specimens = entities[:museum_codes]
      orcids = entities[:orcids]

      if found_specimens.count > 0
        bulk = Array.new(found_specimens.count, citation[:id]).zip(found_specimens)
        specimens.import([:citation_id, :specimen_code], bulk)
      end

      if orcids.count > 0
        bulk = Array.new(orcids.count, citation[:id]).zip(orcids)
        @db[:orcids].import([:citation_id, :orcid], bulk)
      end

      if citation[:doi].nil? && !ee.doi.nil?
        citation[:doi] = ee.doi
      end

      citation[:status] = 4
      update_citation(citation)
    end
  end

  def update_failed_extractions
    citations.where(status: 2).each do |citation|
      citation[:status] = 5
      update_citation(citation)
    end
  end

  def update_metadata
    citations.where(formatted: [nil,""]).exclude(doi: nil).each do |citation|
      citation[:bibtex] = doi_metadata(citation[:doi], "bibtex") rescue nil
      citation[:formatted] = doi_metadata(citation[:doi], "biblio") rescue nil
      json = JSON.parse(doi_metadata(citation[:doi], "csl+json")) rescue nil
      citation[:print_date] = format_pub_date(json["published-print"]["date-parts"][0].join("-")) rescue nil
      if citation[:print_date].nil?
        citation[:print_date] = format_pub_date(json["published-online"]["date-parts"][0].join("-")) rescue nil
      end
      citation[:year] = BibTeX.parse(citation[:bibtex]).first.year.to_i rescue nil
      if [citation[:year], citation[:bibtex]].compact.empty?
        citation[:formatted] = ""
      end
      update_citation(citation)
    end
  end

  def update_reference_style(style)
    citations.exclude(doi: nil).each do |citation|
      citation[:formatted] = doi_metadata(citation[:doi], "biblio", style) rescue nil
      update_citation(citation)
    end
  end

  def write_csv
    csv_file = File.join(root, 'public', 'publications.csv')
    CSV.open(csv_file, 'w') do |csv|
      csv << output_header

      output[:entries].each do |entry|
        csv << output_header.map{ |i| entry[i.to_sym] }
      end
    end
  end

  def write_xlsx
    xlsx_file = File.join(root, 'public', 'publications.xlsx')
    workbook = WriteXLSX.new(xlsx_file)

    worksheet = workbook.add_worksheet

    output_header.each_with_index do |v, i|
      worksheet.write(0, i, v)
    end

    row = 1
    output[:entries].each do |entry|
      (0..14).each do |i|
        worksheet.write(row, i, entry[output_header[i].to_sym])
      end
      row += 1
    end

    workbook.close
  end

  def write_webpage
    template = File.join(root, 'template', "template.slim")
    web_page = File.join(root, 'index.html')
    html = Slim::Template.new(template).render(Object.new, output)
    File.open(web_page, 'w') { |file| file.write(html) }
    html
  end

  private

  def output
    data = {
      generation_time: Time.now.strftime('%Y-%m-%d %H:%M:%S'),
      entries: []
    }
    sql = "SELECT 
        c.id,
        c.md5,
        c.doi,
        c.url,
        c.license,
        c.formatted,
        c.possible_authorship,
        c.possible_citation,
        c.print_date,
        c.year,
        c.keywords,
        c.countries,
        c.created 
      FROM 
        citations c 
      ORDER BY c.print_date DESC"
    @db[sql].each do |row|
      pdf_exists = File.exists?(File.join(root, 'pdfs', "#{row[:md5]}.pdf")) ? true : false
      pdf_url = pdf_exists ? "http://ntracker-01/pdfs/#{row[:md5]}.pdf" : nil
      extras = { 
        specimens: specimens.where(citation_id: row[:id])
                                  .all.map{ |s| s[:specimen_code] }
                                  .join(", "),
        orcids: @db[:orcids].where(citation_id: row[:id])
                            .select_map(:orcid)
                            .join(", "),
        pdf_exists: pdf_exists,
        pdf_url: pdf_url
      }
      data[:entries] << row.merge(extras)
    end
    data
  end

  def output_header
    [
      "md5",
      "doi",
      "url",
      "license",
      "formatted",
      "possible_authorship",
      "possible_citation",
      "print_date",
      "year",
      "keywords",
      "created",
      "specimens",
      "orcids",
      "countries",
      "pdf_url"
    ]
  end

  def root
    File.dirname(File.dirname(__FILE__))
  end

  def parse_config
    config = YAML.load_file(@config_file).deep_symbolize_keys!
    env = ENV.key?("ENVIRONMENT") ? ENV["ENVIRONMENT"] : "development"
    config[env.to_sym]
  end

  def doi_metadata(doi, output_format = 'biblio', style = 'apa')
    url = "https://doi.org/" + URI.escape(doi)

    case output_format
    when 'biblio'
      header = { Accept: "text/x-bibliography; style=#{style}" }
    when 'bibtex'
      header = { Accept: "application/x-bibtex" }
    when 'csl+json'
      header = { Accept: "application/vnd.citationstyles.csl+json" }
    else
      header = { Accept: "text/x-bibliography; style=#{style}" }
    end

    begin
      req = Typhoeus.get(url, headers: header, followlocation: true)
      if req.response_code == 200
        req.response_body.gsub!(/doi\:\s*/i, "https://doi.org/")
      else
        nil
      end
    rescue
      nil
    end
  end

  def valid_pdf(pdf)
    mime_type = `file --mime -b "#{pdf}"`.chomp
    mime_type.include?("application/pdf")
  end

  def insert_citation(citation)
    citations.insert(citation)
  end

  def update_citation(citation)
    md5 = citation[:md5]
    citation.delete(:md5)
    citations.where(md5: md5).update(citation)
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
    doi_pattern = /(10[.][0-9]{4,}(?:[.][0-9]+)*\/(?:(?![%"#?' ])\S)+)/i
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

  def queued_request(citation)
    pdf = citation_pdf(citation)
    url = citation[:url]
    begin
      downloaded_file = File.open pdf, 'wb'

      req = Typhoeus::Request.new(url, followlocation: true)
      req.on_body do |chunk|
        downloaded_file.write(chunk)
      end
      req.on_complete do |response|
        downloaded_file.close
        if valid_pdf(pdf)
          citation[:status] = 3
          update_citation(citation)
        else
          citation[:status] = 1
          doi = extract_doi(File.read(pdf))
          if citation[:doi].nil? && doi
            citation[:doi] = doi
          end
          File.delete pdf
          update_citation(citation)
        end
      end
    rescue
    end
    req
  end

  def citation_pdf(citation)
    File.join(root, 'pdfs', "#{citation[:md5]}.pdf")
  end

  def format_pub_date(txt)
    date_pattern = /(?<year>\d{4})-?(?<month>\d{1,2})?-?(?<day>\d{1,2})?/
    matches = txt.match(date_pattern)
    year = !matches["year"].nil? ? matches["year"] : nil
    month = !matches["month"].nil? ? matches["month"].rjust(2, "0") : nil
    day = !matches["day"].nil? ? matches["day"].rjust(2, "0") : nil
    [year, month, day].compact.join("-")
  end

end