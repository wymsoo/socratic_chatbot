import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:fl_chart/fl_chart.dart';

void main() {
  runApp(const AnalyticsApp());
}

class AnalyticsApp extends StatelessWidget {
  const AnalyticsApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Confusion Analytics',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: const Color(0xFFF2F5F9), // Soft grayish-blue background
        primaryColor: const Color(0xFF5D7BCA),
        fontFamily: 'Roboto', // Replace with GoogleFonts.poppins() if desired
      ),
      home: DashboardScreen(),
    );
  }
}

class DashboardScreen extends StatefulWidget {
  @override
  _DashboardScreenState createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Map<String, dynamic>? data;
  bool isLoading = true;
  final String _backendUrl = 'http://172.20.10.4:8000';

  // UI Palette based on the image
  final Color primaryBlue = const Color(0xFF5D7BCA);
  final Color softCyan = const Color(0xFF9FD5D1);
  final Color softOrange = const Color(0xFFF3BE7C);
  final Color softGreen = const Color(0xFF86D28F);
  final Color textDark = const Color(0xFF2D3142);
  final Color textMuted = const Color(0xFF9BA1B0);

  @override
  void initState() {
    super.initState();
    fetchData();
  }

  Future<void> fetchData() async {
    try {
      final response = await http.get(Uri.parse('$_backendUrl/api/confusion-data'));
      if (response.statusCode == 200) {
        setState(() {
          data = json.decode(response.body);
          isLoading = false;
        });
      }
    } catch (e) {
      print("Error fetching data: $e");
      // Handle error state appropriately in production
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: primaryBlue),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Row(
          children: [
            Icon(Icons.show_chart, color: primaryBlue, size: 28),
            const SizedBox(width: 8),
            Text(
              'Analytics',
              style: TextStyle(
                color: textDark,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.notifications_none, color: textDark),
            onPressed: () {},
          ),
        ],
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Time Series Chart
            _buildDashboardCard(
              title: 'Confusion Over Time',
              subtitle: 'Timeline of student interactions',
              child: SizedBox(
                height: 220,
                child: _buildTimeSeriesChart(data!['timeSeries']),
              ),
            ),
            const SizedBox(height: 20),

            // 2. Student Leaderboard Bar Chart
            _buildDashboardCard(
              title: 'Most Confused Students',
              subtitle: 'Top 10 highest interaction counts',
              child: SizedBox(
                height: 220,
                child: _buildStudentChart(data!['students']),
              ),
            ),
            const SizedBox(height: 20),

            // 3. Keyword Associations List
            _buildDashboardCard(
              title: 'Keyword Associations',
              subtitle: 'Strongest conceptual links',
              child: _buildAssociationsList(data!['edges']),
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  // --- UI Helpers ---

  Widget _buildDashboardCard({required String title, required String subtitle, required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textDark),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(fontSize: 13, color: textMuted),
          ),
          const SizedBox(height: 24),
          child,
        ],
      ),
    );
  }

  // --- Charts ---

  Widget _buildTimeSeriesChart(List<dynamic> timeSeries) {
    if (timeSeries.isEmpty) return const Center(child: Text("No time data available"));

    final startTime = timeSeries.first['time'];
    
    List<FlSpot> spots = timeSeries.map((point) {
      final double x = ((point['time'] - startTime) / 60000).toDouble(); 
      final double y = point['count'].toDouble();
      return FlSpot(x, y);
    }).toList();

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: 1,
          getDrawingHorizontalLine: (value) {
            return FlLine(color: Colors.grey.withOpacity(0.1), strokeWidth: 1);
          },
        ),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              getTitlesWidget: (value, meta) {
                return Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text('${value.toInt()}m', style: TextStyle(color: textMuted, fontSize: 12)),
                );
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              getTitlesWidget: (value, meta) {
                return Text('${value.toInt()}', style: TextStyle(color: textMuted, fontSize: 12));
              },
            ),
          ),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: primaryBlue,
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false), // Hide dots for a cleaner aesthetic
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                colors: [
                  primaryBlue.withOpacity(0.3),
                  primaryBlue.withOpacity(0.0),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStudentChart(List<dynamic> students) {
    if (students.isEmpty) return const Center(child: Text("No student data"));
    
    final topStudents = students.take(10).toList();
    
    List<BarChartGroupData> barGroups = List.generate(topStudents.length, (index) {
      return BarChartGroupData(
        x: index,
        barRods: [
          BarChartRodData(
            toY: topStudents[index]['count'].toDouble(),
            // Alternating colors based on the image palette
            color: index % 3 == 0 ? softCyan : (index % 3 == 1 ? primaryBlue : softOrange),
            width: 12,
            borderRadius: BorderRadius.circular(6),
            backDrawRodData: BackgroundBarChartRodData(
              show: true,
              toY: 10, // Max mock value for the grey background track
              color: Colors.grey.withOpacity(0.1),
            )
          )
        ],
      );
    });

    return BarChart(
      BarChartData(
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                if (value.toInt() >= topStudents.length) return const Text('');
                String name = topStudents[value.toInt()]['student'].toString();
                // Extract last digit of S001, S002 etc. for cleaner display
                String label = name.length > 3 ? name.substring(3) : name;
                return Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(label, style: TextStyle(color: textMuted, fontSize: 12, fontWeight: FontWeight.bold)),
                );
              },
            ),
          ),
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        barGroups: barGroups,
      ),
    );
  }

  // Replacing the DataTable with a cleaner ListView
  Widget _buildAssociationsList(List<dynamic> edges) {
    if (edges.isEmpty) return const Text("No association data");
    
    // Take top 8 associations
    final topEdges = edges.take(8).toList();

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: topEdges.length,
      separatorBuilder: (context, index) => Divider(color: Colors.grey.withOpacity(0.2), height: 1),
      itemBuilder: (context, index) {
        final edge = topEdges[index];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 12.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: softGreen,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '${edge['source']} ↔ ${edge['target']}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: textDark,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: softCyan.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${edge['weight']}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: primaryBlue,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}