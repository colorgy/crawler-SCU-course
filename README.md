東吳課程爬蟲
===========

`spider.rb` 是純用 Capybara 寫的，`scu_course_crawler.rb` 是混用 Capybara 和 RestClient 。

順帶一提，太頻繁抓會有流量限制，這邊還沒有做 error handling。

![traffic](doc/img/bandwidth.png)
