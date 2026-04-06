package com.bokkyun.teamsync

import java.util.Calendar
import java.util.Locale
import org.json.JSONArray
import org.json.JSONException

internal data class WEvent(val startMs: Long, val endMs: Long, val title: String, val allDay: Boolean)

internal object TeamSyncWidgetCalendar {

  const val PREFS_NAME = "HomeWidgetPreferences"
  const val KEY_EVENTS_JSON = "ts_events_json"
  const val KEY_ANCHOR_MS = "ts_anchor_ms"
  const val KEY_VIEW_MODE = "ts_view_mode"

  const val MODE_DAY = 0
  const val MODE_WEEK = 1
  const val MODE_MONTH = 2

  fun parseEvents(json: String?): List<WEvent> {
    if (json.isNullOrBlank()) return emptyList()
    return try {
      val arr = JSONArray(json)
      buildList {
        for (i in 0 until arr.length()) {
          val o = arr.getJSONObject(i)
          val s = o.optLong("s", 0L)
          val e = o.optLong("e", s)
          val t = o.optString("t", "")
          val a = o.optInt("a", 0) == 1
          if (s > 0) add(WEvent(s, e, t, a))
        }
      }
    } catch (_: JSONException) {
      emptyList()
    }
  }

  fun startOfDay(cal: Calendar): Calendar {
    val c = cal.clone() as Calendar
    c.set(Calendar.HOUR_OF_DAY, 0)
    c.set(Calendar.MINUTE, 0)
    c.set(Calendar.SECOND, 0)
    c.set(Calendar.MILLISECOND, 0)
    return c
  }

  fun overlapsDay(ev: WEvent, day: Calendar): Boolean {
    val d0 = startOfDay(day).timeInMillis
    val next = (startOfDay(day).clone() as Calendar).apply { add(Calendar.DAY_OF_MONTH, 1) }
    val d1 = next.timeInMillis
    return ev.startMs < d1 && ev.endMs > d0
  }

  /** 일요일 시작 주간: anchor가 속한 주의 일~토 */
  fun weekRangeLabel(anchor: Calendar): String {
    val sun = startOfDay(anchor).clone() as Calendar
    while (sun.get(Calendar.DAY_OF_WEEK) != Calendar.SUNDAY) {
      sun.add(Calendar.DAY_OF_MONTH, -1)
    }
    val sat = sun.clone() as Calendar
    sat.add(Calendar.DAY_OF_MONTH, 6)
    val m1 = sun.get(Calendar.MONTH) + 1
    val d1 = sun.get(Calendar.DAY_OF_MONTH)
    val m2 = sat.get(Calendar.MONTH) + 1
    val d2 = sat.get(Calendar.DAY_OF_MONTH)
    return if (m1 == m2) {
      "$m1/$d1–$d2"
    } else {
      "$m1/$d1–$m2/$d2"
    }
  }

  fun dayHeader(anchor: Calendar): String {
    val m = anchor.get(Calendar.MONTH) + 1
    val d = anchor.get(Calendar.DAY_OF_MONTH)
    val w = anchor.getDisplayName(Calendar.DAY_OF_WEEK, Calendar.SHORT, Locale.KOREA) ?: ""
    return "${m}월 ${d}일 ($w)"
  }

  fun buildDayBody(anchor: Calendar, events: List<WEvent>): String {
    val list =
        events.filter { overlapsDay(it, anchor) }.sortedBy { it.startMs }
    if (list.isEmpty()) return "일정이 없습니다"
    return list.joinToString("\n") { ev ->
      val time =
          if (ev.allDay) {
            "종일"
          } else {
            val c = Calendar.getInstance().apply { timeInMillis = ev.startMs }
            String.format("%02d:%02d", c.get(Calendar.HOUR_OF_DAY), c.get(Calendar.MINUTE))
          }
      "$time ${ev.title}"
    }
  }

  fun buildWeekBody(anchor: Calendar, events: List<WEvent>): String {
    val sun = startOfDay(anchor).clone() as Calendar
    while (sun.get(Calendar.DAY_OF_WEEK) != Calendar.SUNDAY) {
      sun.add(Calendar.DAY_OF_MONTH, -1)
    }
    val sb = StringBuilder()
    for (i in 0 until 7) {
      val day = sun.clone() as Calendar
      day.add(Calendar.DAY_OF_MONTH, i)
      val m = day.get(Calendar.MONTH) + 1
      val dom = day.get(Calendar.DAY_OF_MONTH)
      val w = day.getDisplayName(Calendar.DAY_OF_WEEK, Calendar.SHORT, Locale.KOREA) ?: ""
      val dayEvents = events.filter { overlapsDay(it, day) }.sortedBy { it.startMs }
      sb.append("$w $m/$dom")
      if (dayEvents.isEmpty()) {
        sb.append("  —\n")
      } else {
        sb.append('\n')
        for (ev in dayEvents.take(3)) {
          val t =
              if (ev.allDay) {
                "종일"
              } else {
                val c = Calendar.getInstance().apply { timeInMillis = ev.startMs }
                String.format("%02d:%02d", c.get(Calendar.HOUR_OF_DAY), c.get(Calendar.MINUTE))
              }
          sb.append("  $t ${ev.title}\n")
        }
        if (dayEvents.size > 3) sb.append("  … 외 ${dayEvents.size - 3}건\n")
      }
    }
    return sb.toString().trimEnd()
  }

  data class MonthCell(val text: String, val inMonth: Boolean, val hasEvent: Boolean, val isToday: Boolean)

  fun buildMonthCells(anchor: Calendar, events: List<WEvent>): Pair<String, List<MonthCell>> {
    val monthCal = anchor.clone() as Calendar
    monthCal.set(Calendar.DAY_OF_MONTH, 1)
    monthCal.set(Calendar.HOUR_OF_DAY, 0)
    monthCal.set(Calendar.MINUTE, 0)
    monthCal.set(Calendar.SECOND, 0)
    monthCal.set(Calendar.MILLISECOND, 0)

    val y = monthCal.get(Calendar.YEAR)
    val mo = monthCal.get(Calendar.MONTH)
    val header = "${y}년 ${mo + 1}월"

    val first = monthCal.clone() as Calendar
    while (first.get(Calendar.DAY_OF_WEEK) != Calendar.SUNDAY) {
      first.add(Calendar.DAY_OF_MONTH, -1)
    }

    val todayMs = startOfDay(Calendar.getInstance()).timeInMillis
    val cells = ArrayList<MonthCell>(42)
    val cur = first.clone() as Calendar
    for (i in 0 until 42) {
      val inMonth = cur.get(Calendar.MONTH) == mo
      val dom = cur.get(Calendar.DAY_OF_MONTH)
      val text =
          if (inMonth) {
            dom.toString()
          } else {
            ""
          }
      val hasEvent = events.any { overlapsDay(it, cur) }
      val isToday = startOfDay(cur).timeInMillis == todayMs
      cells.add(MonthCell(text, inMonth, hasEvent, isToday))
      cur.add(Calendar.DAY_OF_MONTH, 1)
    }
    return header to cells
  }
}
