#!/bin/env ruby
# encoding: utf-8

require 'scraperwiki'
require 'nokogiri'
require 'open-uri/cached'
require 'pry'

class String
  def tidy
    self.gsub(/[[:space:]]+/, ' ').strip
  end
end

def noko_for(url)
  Nokogiri::HTML(open(url).read)
end

def scrape_term(term, url)
  page = noko_for url

  term_details = page.css('div.TITULO_CONTENIDO').text.tidy
  matched = term_details.match('(^[^\(]*)\s+\(([^\)]*)\)')
  if matched
    term_name, dates = matched.captures
    matched_dates = dates.match('(\d+)\s*-\s*(.*)')
    if matched_dates
      start_date, end_date = matched_dates.captures
    end
  end

  data = {
      id: term,
      name: term_name.tidy,
      source: url.to_s,
      start_date: start_date.tidy,
  }

  if end_date.tidy != 'Actualidad'
    data[:end_date] = end_date.tidy
  end

  ScraperWiki.save_sqlite([:id], data, 'terms')
  scrape_people(term, url)
end

def scrape_people(term, url)
  page = noko_for url

  page.css('div#RESULTADOS_DIPUTADOS div.listado_1 ul li a/@href').each do |href|
    scrape_person(term, URI.join(url, href))
  end

  pagination = page.css('div.paginacion').first
  next_page = pagination.xpath(".//a[contains(.,'Página Siguiente')]/@href")
  unless next_page[0].nil?
    scrape_people(term, next_page[0].value)
  end
end

def month(str)
  ['','enero','febrero','marzo','abril','mayo','junio','julio','agosto','septiembre','octubre','noviembre','diciembre'].find_index(str) or raise "Unknown month #{str}".magenta
end

def scrape_person(term, url)
    person = noko_for(url)

    details = person.css('div#curriculum')

    name = details.css('div.nombre_dip').text
    family_names, given_names = name.split(/,/).partition { |w| w == w.upcase }
    print_name = ( given_names + family_names ).join(' ')

    bio = details.css('div.texto_dip')
    seat_and_faction = bio[0].css('ul li div.dip_rojo')
    other = bio[1]

    seat = seat_and_faction[0].text.tidy
    faction = seat_and_faction[1].nil? ? '' : seat_and_faction[1].text.tidy

    photo_and_party = person.css('div#datos_diputado')
    photo = photo_and_party.css('p.logo_grupo img[name=foto]/@src').text
    if photo
        photo_url = URI.join(url, photo)
    end

    party = photo_and_party.css('p.nombre_grupo').text.tidy

    dob_string = other.css('ul li').first.text.tidy
    dob = ''
    if matched = dob_string.match(/(\d+) de ([^[:space:]]*) de (\d+)/)
        day, month, year = matched.captures
        dob = "%d-%02d-%02d" % [ year, month(month), day ]
    end

    contacts = bio.css('div.webperso_dip')

    email = contacts.xpath('..//a[@href[contains(.,"mailto")]]').text.tidy
    twitter = contacts.xpath('..//a[@href[contains(.,"twitter")]]/@href').text.tidy

    data = {
        id: url.to_s[/idDiputado=(\d+)/, 1],
        name: print_name,
        sort_name: name,
        given_name: given_names.join(' '),
        family_name: family_names.join(' '),
        faction: faction,
        party: party,
        source: url.to_s,
        dob: dob,
        term: term,
        email: email,
        twitter: twitter,
        photo: photo_url.to_s,
        constituency: seat,
    }

    #puts "%s - %s - %s - %s\n" % [ name, dob, seat, twitter]
    ScraperWiki.save_sqlite([:id, :term], data)
end

(1..11).reverse_each do |term, url|
  puts term
  url = 'http://www.congreso.es/portal/page/portal/Congreso/Congreso/Diputados?_piref73_1333056_73_1333049_1333049.next_page=/wc/menuAbecedarioInicio&tipoBusqueda=completo&idLegislatura=%d' % term
  scrape_term(term, url)
end
