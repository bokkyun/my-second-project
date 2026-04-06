package com.bokkyun.teamsync

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.Color
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import java.util.Calendar

class TeamSyncWidgetProvider : HomeWidgetProvider() {

  override fun onUpdate(
      context: Context,
      appWidgetManager: AppWidgetManager,
      appWidgetIds: IntArray,
      widgetData: SharedPreferences,
  ) {
    val eventsJson = widgetData.getString(TeamSyncWidgetCalendar.KEY_EVENTS_JSON, null)
    val events = TeamSyncWidgetCalendar.parseEvents(eventsJson)

    var anchorMs = widgetData.getLong(TeamSyncWidgetCalendar.KEY_ANCHOR_MS, System.currentTimeMillis())
    val anchor = TeamSyncWidgetCalendar.startOfDay(Calendar.getInstance().apply { timeInMillis = anchorMs })
    val mode = widgetData.getInt(TeamSyncWidgetCalendar.KEY_VIEW_MODE, TeamSyncWidgetCalendar.MODE_MONTH)

    val openPi = HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java)

    fun pi(cmd: String): PendingIntent {
      val i = Intent(context, TeamSyncWidgetActionReceiver::class.java).apply {
        action = TeamSyncWidgetActionReceiver.ACTION_WIDGET
        putExtra(TeamSyncWidgetActionReceiver.EXTRA_CMD, cmd)
      }
      return PendingIntent.getBroadcast(
          context,
          cmd.hashCode(),
          i,
          PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
      )
    }

    appWidgetIds.forEach { widgetId ->
      val views = RemoteViews(context.packageName, R.layout.teamsync_widget)

      views.setOnClickPendingIntent(R.id.widget_brand, openPi)
      views.setTextViewText(
          R.id.widget_subway_summary,
          widgetData.getString(
              "ts_subway_summary",
              "Set subway routes in app to show ETA.",
          ),
      )
      views.setOnClickPendingIntent(R.id.widget_subway_summary, openPi)
      views.setOnClickPendingIntent(R.id.widget_period_title, openPi)
      views.setOnClickPendingIntent(R.id.btn_prev, pi(TeamSyncWidgetActionReceiver.CMD_PREV))
      views.setOnClickPendingIntent(R.id.btn_next, pi(TeamSyncWidgetActionReceiver.CMD_NEXT))
      views.setOnClickPendingIntent(R.id.btn_mode_day, pi(TeamSyncWidgetActionReceiver.CMD_MODE_DAY))
      views.setOnClickPendingIntent(R.id.btn_mode_week, pi(TeamSyncWidgetActionReceiver.CMD_MODE_WEEK))
      views.setOnClickPendingIntent(R.id.btn_mode_month, pi(TeamSyncWidgetActionReceiver.CMD_MODE_MONTH))

      views.setInt(R.id.btn_mode_day, "setBackgroundResource", R.drawable.widget_chip_bg_neutral)
      views.setInt(R.id.btn_mode_week, "setBackgroundResource", R.drawable.widget_chip_bg_neutral)
      views.setInt(R.id.btn_mode_month, "setBackgroundResource", R.drawable.widget_chip_bg_neutral)
      when (mode) {
        TeamSyncWidgetCalendar.MODE_DAY ->
            views.setInt(R.id.btn_mode_day, "setBackgroundResource", R.drawable.widget_chip_bg)
        TeamSyncWidgetCalendar.MODE_WEEK ->
            views.setInt(R.id.btn_mode_week, "setBackgroundResource", R.drawable.widget_chip_bg)
        TeamSyncWidgetCalendar.MODE_MONTH ->
            views.setInt(R.id.btn_mode_month, "setBackgroundResource", R.drawable.widget_chip_bg)
      }

      when (mode) {
        TeamSyncWidgetCalendar.MODE_DAY -> {
          views.setViewVisibility(R.id.panel_day, android.view.View.VISIBLE)
          views.setViewVisibility(R.id.panel_week, android.view.View.GONE)
          views.setViewVisibility(R.id.panel_month, android.view.View.GONE)
          views.setViewVisibility(R.id.widget_day_header, android.view.View.GONE)
          views.setTextViewText(R.id.widget_period_title, TeamSyncWidgetCalendar.dayHeader(anchor))
          views.setTextViewText(
              R.id.widget_day_events,
              TeamSyncWidgetCalendar.buildDayBody(anchor, events),
          )
          views.setOnClickPendingIntent(R.id.widget_day_events, openPi)
          views.setOnClickPendingIntent(R.id.panel_day, openPi)
        }
        TeamSyncWidgetCalendar.MODE_WEEK -> {
          views.setViewVisibility(R.id.panel_day, android.view.View.GONE)
          views.setViewVisibility(R.id.panel_week, android.view.View.VISIBLE)
          views.setViewVisibility(R.id.panel_month, android.view.View.GONE)
          views.setTextViewText(R.id.widget_period_title, TeamSyncWidgetCalendar.weekRangeLabel(anchor))
          views.setTextViewText(R.id.widget_week_text, TeamSyncWidgetCalendar.buildWeekBody(anchor, events))
          views.setOnClickPendingIntent(R.id.widget_week_text, openPi)
          views.setOnClickPendingIntent(R.id.panel_week, openPi)
        }
        TeamSyncWidgetCalendar.MODE_MONTH -> {
          views.setViewVisibility(R.id.panel_day, android.view.View.GONE)
          views.setViewVisibility(R.id.panel_week, android.view.View.GONE)
          views.setViewVisibility(R.id.panel_month, android.view.View.VISIBLE)
          val (header, cells) = TeamSyncWidgetCalendar.buildMonthCells(anchor, events)
          views.setTextViewText(R.id.widget_period_title, header)
          for (i in MCELL_IDS.indices) {
            val cell = cells[i]
            val label =
                when {
                  cell.text.isEmpty() -> ""
                  cell.hasEvent -> "${cell.text}·"
                  else -> cell.text
                }
            views.setTextViewText(MCELL_IDS[i], label)
            val color =
                when {
                  !cell.inMonth -> Color.parseColor("#BDBDBD")
                  cell.isToday -> Color.parseColor("#1565C0")
                  cell.hasEvent -> Color.parseColor("#424242")
                  else -> Color.parseColor("#757575")
                }
            views.setTextColor(MCELL_IDS[i], color)
            views.setOnClickPendingIntent(MCELL_IDS[i], openPi)
          }
          views.setOnClickPendingIntent(R.id.panel_month, openPi)
        }
      }

      appWidgetManager.updateAppWidget(widgetId, views)
    }
  }

  companion object {
    private val MCELL_IDS =
        intArrayOf(
            R.id.mcell_0,
            R.id.mcell_1,
            R.id.mcell_2,
            R.id.mcell_3,
            R.id.mcell_4,
            R.id.mcell_5,
            R.id.mcell_6,
            R.id.mcell_7,
            R.id.mcell_8,
            R.id.mcell_9,
            R.id.mcell_10,
            R.id.mcell_11,
            R.id.mcell_12,
            R.id.mcell_13,
            R.id.mcell_14,
            R.id.mcell_15,
            R.id.mcell_16,
            R.id.mcell_17,
            R.id.mcell_18,
            R.id.mcell_19,
            R.id.mcell_20,
            R.id.mcell_21,
            R.id.mcell_22,
            R.id.mcell_23,
            R.id.mcell_24,
            R.id.mcell_25,
            R.id.mcell_26,
            R.id.mcell_27,
            R.id.mcell_28,
            R.id.mcell_29,
            R.id.mcell_30,
            R.id.mcell_31,
            R.id.mcell_32,
            R.id.mcell_33,
            R.id.mcell_34,
            R.id.mcell_35,
            R.id.mcell_36,
            R.id.mcell_37,
            R.id.mcell_38,
            R.id.mcell_39,
            R.id.mcell_40,
            R.id.mcell_41,
        )
  }
}
