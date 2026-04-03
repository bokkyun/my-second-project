package com.bokkyun.teamsync

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

class TeamSyncWidgetProvider : HomeWidgetProvider() {

  override fun onUpdate(
      context: Context,
      appWidgetManager: AppWidgetManager,
      appWidgetIds: IntArray,
      widgetData: SharedPreferences,
  ) {
    appWidgetIds.forEach { widgetId ->
      val views =
          RemoteViews(context.packageName, R.layout.teamsync_widget).apply {
            setTextViewText(R.id.widget_title, "TeamSync")
            setTextViewText(
                R.id.widget_subtitle,
                widgetData.getString("ts_subtitle", null) ?: "오늘 일정을 불러오려면 앱을 실행하세요",
            )
            setTextViewText(
                R.id.widget_detail,
                widgetData.getString("ts_detail", null) ?: "",
            )

            val pendingIntent =
                HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java)
            setOnClickPendingIntent(R.id.widget_container, pendingIntent)
          }

      appWidgetManager.updateAppWidget(widgetId, views)
    }
  }
}
