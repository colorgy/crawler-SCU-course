require 'crawler_rocks'

require 'capybara'
require 'capybara/poltergeist'

require 'iconv'
require 'json'
require 'pry'

require 'thread'
require 'thwait'

class ScuCourseCrawler
  # include CrawlerRocks::DSL
  include Capybara::DSL
  include RestClient

  DAYS = {
    "一" => 1,
    "二" => 2,
    "三" => 3,
    "四" => 4,
    "五" => 5,
    "六" => 6,
    "日" => 7,
  }

  def initialize year: current_year, term: current_term, update_progress: nil, after_each: nil, params: nil

    # @base_url = "http://www.is.cgu.edu.tw/portal/"
    @query_url = "http://web.sys.scu.edu.tw/class401.asp"
    @result_url = "http://web.sys.scu.edu.tw/class42.asp"


    @year = params && params["year"].to_i || year
    @term = params && params["term"].to_i || term
    @update_progress_proc = update_progress
    @after_each_proc = after_each

    Capybara.register_driver :poltergeist do |app|
      Capybara::Poltergeist::Driver.new(app,  js_errors: false)
    end

    Capybara.javascript_driver = :poltergeist
    Capybara.current_driver = :poltergeist

    @ic = Iconv.new("utf-8//translit//IGNORE","big5")
    @ic2 = Iconv.new("big5//translit//IGNORE","utf-8")
  end

  def courses
    @courses_h = {}
    page.visit @query_url

    # prepare post hash
    post_datas = []
    index = 0
    page.all('select[name="clsid1"] option').each do |type_option|
      type_option.select_option
      _type = type_option.text
      _type_v = type_option[:value]

      page.all('select[name="clsid02"] option').each do |department_option|
        department_option.select_option
        _department = department_option.text
        _department_v = department_option[:value]

        page.all('select[name="clsid34"] option').each do |class_option|
          # class_option.select_option
          _class = class_option.text
          _class_v = class_option[:value]

          post_datas[index] = {
            clsid1: CGI.escape(_type_v.encode('big5')),
            clsid02: CGI.escape(_department_v.encode('big5')),
            clsid34: CGI.escape(_class_v.encode('big5')),
            _type: _type_v,
            _department: _department_v,
            _class: _class_v
          }
          index += 1
        end
      end
    end

    puts "parse datas..."

    refresh_page
    post_datas.each_with_index do |post_data, index|
      puts "#{index} / #{post_datas.count}"
      r = RestClient.post(@result_url, post_data.merge({
        syear: @year-1911,
        smester: @term
      }), cookies: @cookies) do |response, request, result, &block|
      if [500].include? response.code
        puts "500 Internal Error"
        next
      else
        response.return!(request, result, &block)
      end
    end

      doc = Nokogiri::HTML(@ic.iconv(r))
      if doc.css('table tr')[1..-1].nil?
        refresh_page
        @redo_count ||= 0
        @redo_count += 1
        if @redo_count < 10
          redo
        else
          @redo_count = 0
          next
        end
      end
      doc.css('table tr')[1..-1] && doc.css('table tr')[1..-1].each do |row|
        datas = row.css('td')
        url = !datas[3].css('a').empty? && datas[3].css('a')[0][:href].prepend("http://web.sys.scu.edu.tw")
        code = datas[2] && "#{@year}-#{@term}-#{datas[2].text.strip.gsub(/ /, '')}"
        # TODOs: parse detail page

        @courses_h[code] ||= {
          year: @year,
          term: @term,
          code: code,
          department: post_data[:_department].match(/[^\d]+/)[0],
          name: datas[3] && datas[3].text.strip,
          url: url,
          # full_or_half: datas[5].text.strip.gsub(/ /, '') == '全',
          required: datas[6] && datas[6].text.strip.gsub(/ /, '') == '必',
          credits: datas[7] && datas[7].text.to_i,
          lecturer: datas[10] && datas[10].text.strip.gsub(/ /, '')
        }

      end
    end # post_datas.each do
    @threads = []
    parse_detail
    ThreadsWait.all_waits(*@threads)

    @courses = @courses_h.map{|k, v| v}
    File.write('courses.json', JSON.pretty_generate(@courses))
  end # end courses

  def parse_detail
    @courses_h.each_with_index do |(code, course), index|
      sleep(1) until (
        @threads.delete_if { |t| !t.status };  # remove dead (ended) threads
        @threads.count < ( (ENV['MAX_THREADS'] && ENV['MAX_THREADS'].to_i) || 30)
      )
      @threads << Thread.new do
        puts "#{index} / #{@courses_h.keys.count}"
        begin
          r = RestClient.get course[:url]
        rescue
          next
        end
        doc = Nokogiri::HTML(@ic.iconv r)

        m = doc.xpath('//comment()').text.gsub(/\r\n\t/, ' ').match(/Classroom：(.+)\<\/font/)
        location = m && m[1].strip || nil
        course_days = []
        course_periods = []
        course_locations = []
        # [["二", "78"], ["五", "34"]]
        doc.css('td:contains("星期節次")').text.split('：').last.scan(/(?<d>[#{DAYS.keys.join}])(?<ps>\d+)/).each do |m|
          m[1].split('').each do |p|
            course_days << DAYS[m[0]]
            course_periods << p.to_i
            course_locations << location
          end
        end

        @courses_h[code][:day_1] = course_days[0]
        @courses_h[code][:day_2] = course_days[1]
        @courses_h[code][:day_3] = course_days[2]
        @courses_h[code][:day_4] = course_days[3]
        @courses_h[code][:day_5] = course_days[4]
        @courses_h[code][:day_6] = course_days[5]
        @courses_h[code][:day_7] = course_days[6]
        @courses_h[code][:day_8] = course_days[7]
        @courses_h[code][:day_9] = course_days[8]
        @courses_h[code][:period_1] = course_periods[0]
        @courses_h[code][:period_2] = course_periods[1]
        @courses_h[code][:period_3] = course_periods[2]
        @courses_h[code][:period_4] = course_periods[3]
        @courses_h[code][:period_5] = course_periods[4]
        @courses_h[code][:period_6] = course_periods[5]
        @courses_h[code][:period_7] = course_periods[6]
        @courses_h[code][:period_8] = course_periods[7]
        @courses_h[code][:period_9] = course_periods[8]
        @courses_h[code][:location_1] = course_locations[0]
        @courses_h[code][:location_2] = course_locations[1]
        @courses_h[code][:location_3] = course_locations[2]
        @courses_h[code][:location_4] = course_locations[3]
        @courses_h[code][:location_5] = course_locations[4]
        @courses_h[code][:location_6] = course_locations[5]
        @courses_h[code][:location_7] = course_locations[6]
        @courses_h[code][:location_8] = course_locations[7]
        @courses_h[code][:location_9] = course_locations[8]
      end
    end # end Thread do
  end

  def refresh_page
    r = RestClient.get @query_url
    @cookies = r.cookies
  end

  def current_year
    (Time.now.month.between?(1, 7) ? Time.now.year - 1 : Time.now.year)
  end

  def current_term
    (Time.now.month.between?(2, 7) ? 2 : 1)
  end
end

cc = ScuCourseCrawler.new(year: 2014, term: 1)
cc.courses
