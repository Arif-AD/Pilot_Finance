import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:pilot_finance/providers/theme_provider.dart';
import 'package:pilot_finance/screens/riwayat_screen.dart';
import 'package:pilot_finance/screens/riwayat_download_screen.dart';
import '../screens/home_screen.dart';
import '../screens/kelola_screen.dart';
import '../screens/rekap_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with TickerProviderStateMixin {
  int currentIndex = 0;
  late AnimationController _animationController;
  late ThemeProvider _themeProvider;
  late final List<Widget> pages;

  final List<String> labels = ['Jasa', 'Kelola', 'Riwayat', 'Rekap', 'Unduhan'];
  final List<IconData> icons = [
    Icons.home_outlined,
    Icons.inventory_2_outlined,
    Icons.receipt_long_outlined,
    Icons.pie_chart_outline,
    Icons.download_outlined,
  ];

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _themeProvider = ThemeProvider();
    _themeProvider.addListener(_onThemeChanged);
    pages = [
      const HomeScreen(),
      const KelolaScreen(),
      const RiwayatScreen(),
      const RekapScreen(),
      const RiwayatDownloadScreen(),
    ];
  }

  void _onThemeChanged() {
    setState(() {});
  }

  @override
  void dispose() {
    _animationController.dispose();
    _themeProvider.removeListener(_onThemeChanged);
    super.dispose();
  }

  void _updateIndex(int newIndex) {
    _animationController.forward(from: 0);

    setState(() {
      currentIndex = newIndex;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = _themeProvider.isDarkMode;
    // Navbar hanya berubah tema gelap saat di Rekap Screen (index 3), untuk halaman lain selalu terang
    final navbarIsDark = currentIndex == 3 && isDark;
    
    return Scaffold(
      body: IndexedStack(
        index: currentIndex,
        children: pages,
      ),
      bottomNavigationBar: ModernCurvedNavBar(
        items: List.generate(
          pages.length,
          (index) => NavItem(
            icon: icons[index],
            label: labels[index],
            isActive: currentIndex == index,
          ),
        ),
        currentIndex: currentIndex,
        onTap: _updateIndex,
        animationController: _animationController,
        isDarkMode: navbarIsDark,
      ),
    );
  }
}

// ==================== MODERN CURVED NAV BAR ====================

class NavItem {
  final IconData icon;
  final String label;
  final bool isActive;

  NavItem({
    required this.icon,
    required this.label,
    required this.isActive,
  });
}

class ModernCurvedNavBar extends StatelessWidget {
  final List<NavItem> items;
  final int currentIndex;
  final Function(int) onTap;
  final AnimationController animationController;
  final bool isDarkMode;

  const ModernCurvedNavBar({
    Key? key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
    required this.animationController,
    this.isDarkMode = false,
  }) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 80,
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF1E1E2E) : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Color(0xFF0B63D4).withOpacity(isDarkMode ? 0.06 : 0.08),
            blurRadius: 18,
            offset: const Offset(0, -6),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(isDarkMode ? 0.06 : 0.03),
            blurRadius: 6,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: List.generate(
          items.length,
          (index) => _NavBarItem(
            item: items[index],
            onTap: () => onTap(index),
            isActive: currentIndex == index,
            index: index,
            totalItems: items.length,
            currentIndex: currentIndex,
            navIsDark: isDarkMode,
          ),
        ),
      ),
    );
  }
}

class _NavBarItem extends StatefulWidget {
  final NavItem item;
  final VoidCallback onTap;
  final bool isActive;
  final int index;
  final int totalItems;
  final int currentIndex;
  final bool navIsDark;

  const _NavBarItem({
    Key? key,
    required this.item,
    required this.onTap,
    required this.isActive,
    required this.index,
    required this.totalItems,
    required this.currentIndex,
    this.navIsDark = false,
  }) : super(key: key);

  @override
  State<_NavBarItem> createState() => _NavBarItemState();
}

class _NavBarItemState extends State<_NavBarItem>
    with SingleTickerProviderStateMixin {
  late AnimationController _scaleController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.elasticOut),
    );
    if (widget.isActive) {
      _scaleController.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(_NavBarItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _scaleController.forward();
    } else if (!widget.isActive && oldWidget.isActive) {
      _scaleController.reverse();
    }
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: () {
          widget.onTap();
          if (widget.isActive) {
            _scaleController.forward(from: 0);
          }
        },
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ScaleTransition(
              scale: _scaleAnimation,
              child: widget.isActive
                    ? Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF0B63D4), Color(0xFF4EA8FF)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Color(0xFF0B63D4).withValues(alpha: 0.22),
                            blurRadius: 6,
                            spreadRadius: 0.2,
                            offset: const Offset(0, 2),
                          )
                        ],
                      ),
                      child: Icon(widget.item.icon, color: Colors.white, size: 22),
                    )
                  : ClipOval(
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                        child: Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: widget.navIsDark
                                  ? [Colors.white.withValues(alpha: 0.02), Colors.white.withValues(alpha: 0.06)]
                                  : [Colors.white.withValues(alpha: 0.7), Colors.white.withValues(alpha: 0.95)],
                            ),
                            border: Border.all(
                              color: widget.navIsDark ? Colors.white.withValues(alpha: 0.06) : Colors.grey.shade200,
                              width: 1.0,
                            ),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: widget.navIsDark ? 0.06 : 0.03),
                                blurRadius: 4,
                                offset: const Offset(0, 1.5),
                              )
                            ],
                          ),
                            child: Center(
                            child: Icon(
                              widget.item.icon,
                              color: widget.navIsDark ? const Color(0xFF9BBCEB) : const Color(0xFF0B63D4),
                              size: widget.isActive ? 22 : 20,
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 6),
            AnimatedOpacity(
              opacity: widget.isActive ? 1.0 : 0.7,
              duration: const Duration(milliseconds: 300),
              child: Text(
                widget.item.label,
                style: TextStyle(
                  color: widget.isActive
                      ? (widget.navIsDark ? Colors.white : const Color(0xFF0B63D4))
                      : (widget.navIsDark ? Colors.white70 : Colors.grey.shade600),
                  fontSize: widget.isActive ? 12 : 11,
                  fontWeight:
                      widget.isActive ? FontWeight.w700 : FontWeight.w500,
                  letterSpacing: 0.3,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

