Specimen Code Tracker in the Primary Literature
===============================================
Ruby application that downloads Google Scholar alert messages from Gmail and secondarily mines PDFs for museum codes.

Requirements
------------
- Linux-based OS
- ruby 2+
- mysql

Configuration
-------------
1. See https://developers.google.com/gmail/api/quickstart/ruby & do Step 1
2. Create a Google Scholar email alert using whatever search terms are relevant, send it to a gmail account
3. Create a filter in gmail to send messages to a "Scholar" label
4. $ gem install bundler
5. $ bundle install
6. First time execution of ./bin/app.rb will prompt to visit a URL, then copy secret code into command line, subsequent executions will use cached secret from above
7. Adjust contents of regex.yml.sample and config.yml.sample and rename regex.yml and config.yml, respectively
8. Set-up MySQL db from /db

PDF download and scan status codes used
---------------------------------------
- 0: pending, default on record creation
- 1: first pass at downloading PDF directly from publisher failed
- 2: second pass at downloading PDF via unpaywall or from Crossref metadata failed, no further attempts will be made
- 3: PDF downloaded, not yet scanned
- 4: PDF scan complete
- 5: Failed extractions

License
-------
See included [LICENSE-en](LICENSE-en) and [LICENCE-fr](LICENCE-fr).

Disclaimer
----------
This project is in incubation status, is incomplete, and is unstable. It has yet to be fully endorsed by the Canadian Museum of Nature and is unlikely to persist.

Contact
-------
David P. Shorthouse, <dshorthouse@nature.ca>