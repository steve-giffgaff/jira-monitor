

require_relative '../lib/config'
require_relative '../lib/strings'
require_relative '../lib/math'
require_relative '../lib/datetime'
require_relative '../lib/db'

class CycleAndLeadTimes
  def initialize
    @db = dbConnect()
  end

  def getMonthlyData(team = "")
    issues = @db[:issues]

    if (team.empty?)
      data = issues.find({"resDate": { "$exists": 1 }}).sort({"resDate": 1})
    else
      data = issues.find({"projectName": team, "resDate": { "$exists": 1 }}).sort({"resDate": 1})
    end

    results = { :cycleTime => {}, :leadTime => {} }
    data.each do |issue|
      resMonth = monthStamp(issue[:resDate])
      if (!results[:leadTime].key?(resMonth))
        results[:leadTime][resMonth] = []
        results[:cycleTime][resMonth] = []
      end
      results[:leadTime][resMonth] << issue[:leadTime]
      results[:cycleTime][resMonth] << issue[:cycleTime]
    end

    leadTimes = []
    cycleTimes = []
    if (!results[:leadTime].nil?)
      results[:leadTime].keys.each do |month|
        leadTimes << { "x" => month, "y" => average(results[:leadTime][month]) }
        cycleTimes << { "x" => month, "y" => average(results[:cycleTime][month]) }
      end
    end
    results[:leadTime] = leadTimes
    results[:cycleTime] = cycleTimes

    results
  end

  def getSummaryData(team = "")
    summary = @db[:summary]

    if (team.empty?)
      data = summary.find().sort({"date": 1})
    else
      data = summary.find({"projectName": team}).sort({"date": 1})
    end

    results = { :cycleTime => [], :leadTime => [] }
    data.each do |stat|
      results[:cycleTime] << {"x" => timeStamp(stat[:date]), "y" => stat[:cycleTime].to_i}
      results[:leadTime] << {"x" => timeStamp(stat[:date]), "y" => stat[:leadTime].to_i}
    end
    results
  end

  def sendSeriesData(results, id, type = "")
    if (!results[:leadTime].empty? && !results[:cycleTime].empty?)
      seriesData = [
        { name: "Lead Time", color: "#fff", data: results[:leadTime] },
        { name: "Cycle Time", color: "#ff8154", data: results[:cycleTime] }
      ]
      send_event(id,
        series: seriesData,
        prefix_lead: "#{type} Lead Time: ",
        current_lead: sprintf("%.2f", results[:leadTime].last()["y"].to_s),
        prefix_cycle: "#{type} Cycle Time: ",
        current_cycle: sprintf("%.2f", results[:cycleTime].last()["y"].to_s))
      end
  end

  def getStats(team = "")
    issues = @db[:issues]

    if (team.empty?)
      data = issues.find()
    else
      data = issues.find({"projectName": team})
    end
    leadTime = []
    cycleTime = []
    data.each do |stat|
      if (stat[:cycleTime] > 0)
        cycleTime << stat[:cycleTime].to_int
      end

      if (stat[:leadTime] > 0)
        leadTime << stat[:leadTime].to_int
      end
    end

    cycleTimeMean = average(cycleTime)
    leadTimeMean = average(leadTime)
    {
      cycleMean: sprintf("%.2f", cycleTimeMean),
      cycleStdDevMin: sprintf("%d", cycleTimeMean - standardDeviation(cycleTime)),
      cycle2StdDevMin: sprintf("%d", cycleTimeMean - 2 * standardDeviation(cycleTime)),
      cycleStdDevMax: sprintf("%d", cycleTimeMean + standardDeviation(cycleTime)),
      cycle2StdDevMax: sprintf("%d", cycleTimeMean + 2 * standardDeviation(cycleTime)),
      leadMean: sprintf("%d", leadTimeMean),
      leadStdDevMin: sprintf("%d", leadTimeMean - standardDeviation(leadTime)),
      lead2StdDevMin: sprintf("%d", leadTimeMean - 2 * standardDeviation(leadTime)),
      leadStdDevMax: sprintf("%d", leadTimeMean + standardDeviation(leadTime)),
      lead2StdDevMax: sprintf("%d", leadTimeMean + 2 * standardDeviation(leadTime))
    }

  end

  def getDistribution(team = "")
    issues = @db[:issues]

    if (team.empty?)
      data = issues.find()
    else
      data = issues.find({"projectName": team})
    end

    cycleTime = {}
    leadTime = {}
    maxCycleTime = 0
    maxLeadTime = 0
    data.each do |issue|
      if (issue[:cycleTime] > 0)
        if (!cycleTime.key?(issue[:cycleTime]))
          cycleTime[issue[:cycleTime]] = 0
        end
        cycleTime[issue[:cycleTime]] = cycleTime[issue[:cycleTime]] + 1
        if (cycleTime[issue[:cycleTime]] > maxCycleTime)
          maxCycleTime = cycleTime[issue[:cycleTime]]
        end
      end
      if (issue[:leadTime] > 0)
        if (!leadTime.key?(issue[:leadTime]))
          leadTime[issue[:leadTime]] = 0
        end
        leadTime[issue[:leadTime]] = leadTime[issue[:leadTime]] + 1
        if (leadTime[issue[:leadTime]] > maxLeadTime)
          maxLeadTime = leadTime[issue[:leadTime]]
        end
      end
    end

    resultsFile = 'cycle.csv'
    File.delete(resultsFile)
    f = File.open(resultsFile, 'a')
    for i in 0..maxCycleTime do
      n = cycleTime.key?(i) ? cycleTime[i] : 0
      f.write("#{i}, #{n}\n")
    end
    f.close()

    resultsFile = 'lead.csv'
    File.delete(resultsFile)
    f = File.open(resultsFile, 'a')
    for i in 0..maxLeadTime do
      n = leadTime.key?(i) ? leadTime[i] : 0
      f.write("#{i}, #{n}\n")
    end
    f.close()

  end
end

times = CycleAndLeadTimes.new()

SCHEDULER.every "5m", first_in: 0 do |job|

  results = times.getSummaryData()
  times.sendSeriesData(results, 'leadandcycletime')

  $config[:projects].each do |project|
    results = times.getSummaryData(project)
    times.sendSeriesData(results, "leadandcycletime-#{id(project)}")
  end

  monthly = times.getMonthlyData()
  times.sendSeriesData(monthly, 'monthlyleadandcycletime', "Monthly")

  $config[:projects].each do |project|
    results = times.getMonthlyData(project)
    times.sendSeriesData(results, "monthlyleadandcycletime-#{id(project)}", "Monthly")
  end

  stats = times.getStats()
  send_event("stats", stats)

end
