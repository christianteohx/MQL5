#ifndef MYINCLUDE_INDICATORHELPERS_MQH
#define MYINCLUDE_INDICATORHELPERS_MQH

#include <MyInclude/CommonEnums.mqh>
#include <Trade/Trade.mqh>

bool isNewBar() {
    static datetime last_time = 0;
    datetime lastbar_time = (datetime)SeriesInfoInteger(Symbol(), Period(), SERIES_LASTBAR_DATE);

    if (last_time == 0) {
        last_time = lastbar_time;
        return false;
    }

    if (last_time != lastbar_time) {
        last_time = lastbar_time;
        return true;
    }

    return false;
}

bool IsTradingTime() {
    MqlDateTime tm = {};
    datetime time = TimeCurrent(tm);

    // Check if the time is between 10:30 and 11:30
    if ((tm.hour == 17 && tm.min >= 30) || (tm.hour == 18 && tm.min <= 30)) {
        // Print("Time- ", tm.hour, ":", tm.min);
        return true;  // It is within the trading window
    }
    return false;  // It is outside the trading window
}

#endif  // MYINCLUDE_INDICATORHELPERS_MQH