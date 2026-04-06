package com.bokkyun.teamsync

import android.appwidget.AppWidgetManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import java.util.Calendar

class TeamSyncWidgetActionReceiver : BroadcastReceiver() {

  override fun onReceive(context: Context, intent: Intent) {
    if (intent.action != ACTION_WIDGET) return
    val cmd = intent.getStringExtra(EXTRA_CMD) ?: return
    val prefs = context.getSharedPreferences(TeamSyncWidgetCalendar.PREFS_NAME, Context.MODE_PRIVATE)
    val ed = prefs.edit()
    var anchor = Calendar.getInstance().apply { timeInMillis = prefs.getLong(TeamSyncWidgetCalendar.KEY_ANCHOR_MS, System.currentTimeMillis()) }
    anchor = TeamSyncWidgetCalendar.startOfDay(anchor)
    var mode = prefs.getInt(TeamSyncWidgetCalendar.KEY_VIEW_MODE, TeamSyncWidgetCalendar.MODE_MONTH)

    when (cmd) {
      CMD_MODE_DAY -> {
        mode = TeamSyncWidgetCalendar.MODE_DAY
        ed.putInt(TeamSyncWidgetCalendar.KEY_VIEW_MODE, mode)
      }
      CMD_MODE_WEEK -> {
        mode = TeamSyncWidgetCalendar.MODE_WEEK
        ed.putInt(TeamSyncWidgetCalendar.KEY_VIEW_MODE, mode)
      }
      CMD_MODE_MONTH -> {
        mode = TeamSyncWidgetCalendar.MODE_MONTH
        ed.putInt(TeamSyncWidgetCalendar.KEY_VIEW_MODE, mode)
      }
      CMD_PREV -> {
        when (mode) {
          TeamSyncWidgetCalendar.MODE_DAY -> anchor.add(Calendar.DAY_OF_MONTH, -1)
          TeamSyncWidgetCalendar.MODE_WEEK -> anchor.add(Calendar.DAY_OF_MONTH, -7)
          TeamSyncWidgetCalendar.MODE_MONTH -> anchor.add(Calendar.MONTH, -1)
        }
        ed.putLong(TeamSyncWidgetCalendar.KEY_ANCHOR_MS, anchor.timeInMillis)
      }
      CMD_NEXT -> {
        when (mode) {
          TeamSyncWidgetCalendar.MODE_DAY -> anchor.add(Calendar.DAY_OF_MONTH, 1)
          TeamSyncWidgetCalendar.MODE_WEEK -> anchor.add(Calendar.DAY_OF_MONTH, 7)
          TeamSyncWidgetCalendar.MODE_MONTH -> anchor.add(Calendar.MONTH, 1)
        }
        ed.putLong(TeamSyncWidgetCalendar.KEY_ANCHOR_MS, anchor.timeInMillis)
      }
      else -> return
    }
    ed.commit()

    val appWidgetManager = AppWidgetManager.getInstance(context)
    val cn = ComponentName(context, TeamSyncWidgetProvider::class.java)
    val ids = appWidgetManager.getAppWidgetIds(cn)
    val update = Intent(context, TeamSyncWidgetProvider::class.java)
    update.action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
    update.putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
    context.sendBroadcast(update)
  }

  companion object {
    const val ACTION_WIDGET = "com.bokkyun.teamsync.WIDGET_ACTION"
    const val EXTRA_CMD = "cmd"

    const val CMD_MODE_DAY = "mode_day"
    const val CMD_MODE_WEEK = "mode_week"
    const val CMD_MODE_MONTH = "mode_month"
    const val CMD_PREV = "prev"
    const val CMD_NEXT = "next"
  }
}
