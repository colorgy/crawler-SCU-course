require 'capybara'
require 'capybara/webkit'
require 'json'
require 'pry'
require 'nokogiri'
require 'rest_client'
require 'ruby-progressbar'

Capybara.register_driver :selenium_chrome do |app|
  Capybara::Selenium::Driver.new(app, :browser => :chrome)
end

class Spider
  include Capybara::DSL
  attr_accessor :courses

  def initialize
    @courses = []
    Capybara.current_driver = :selenium

    page.visit "http://web.sys.scu.edu.tw/class401.asp"

    page.all('select[name="clsid1"] option').each do |type_option|
      type_option.select_option
      @_type = type_option.text

      page.all('select[name="clsid02"] option').each do |department_option|
        department_option.select_option
        @_department = department_option.text

        page.all('select[name="clsid34"] option').each do |class_option|
          class_option.select_option
          @_class = class_option.text
          page.click_on '查詢'

          current = page.driver.browser.window_handles.first
          course_list = page.driver.browser.window_handles.last
          page.driver.browser.switch_to.window course_list

          parse_list(Nokogiri::HTML(page.html).css('table'))

          page.driver.browser.close
          page.driver.browser.switch_to.window current
        end
      end
    end

  end

  def to_hash_array

  end

  private
    def parse_list(course_table)
      course_table.css('tr:not(:first-child)').each do |row|
        columns = row.css('td')
        url = nil || "http://web.sys.scu.edu.tw#{columns[3].css('a')[0]["href"]}" unless columns[3].css('a').empty?
        @courses << {
          code: columns[2].text.strip.gsub(/ /, ''),
          name: columns[3].text,
          type: @_type,
          department: @_department,
          class: @_class,
          url: url,
          full_or_half: columns[5].text.strip.gsub(/ /, '') == '全',
          required: columns[6].text.strip.gsub(/ /, '') == '必',
          credits: columns[7].text.to_i,
          lecturer: columns[10].text.strip.gsub(/ /, '')
        }

      end
    end

    def parse_detail

    end

end

spider = Spider.new
binding.pry
File.open('courses.json', 'w') { |f| f.write(JSON.pretty_generate(spider.courses)) }


