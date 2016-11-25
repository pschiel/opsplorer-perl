#!/usr/bin/perl

# TODO
# buttons: home, back, forward, up
# color different filetypes (dir/link/..)

# modules
use strict;
use File::Copy;
use Gtk;

# variables
# global variables
my $window;
my $menu;
my $buttonbox;
my $hpaned;
my $ctree;
my $ctree_dest;
my $drag_data;
my $drag_delete_data;
my $statusbar;
my $clist;
my $path;
my $burn_cd_vpaned;
my $burn_cd_clist;
my $vim_socket;
my $vim_socket_id;
my $vim_mode = 0;
my $active_widget;
my $true = 1;
my $false = 0;
my $clist_show_dirs = $true;
my $show_hidden_files = $false;
my @target_table = (
	{ 'target' => "STRING", 'flags' => 1, 'info' => 0 },
	{ 'target' => "text/plain", 'flags' => 0,'info' => 0 },
	{ 'target' => "application/x-rootwin-drop", 'flags' => 0, 'info' => 1 },
);
# menu items
my @menu_items = (
	{ path => '/_File', type => '<Branch>' },
	{ path => '/File/ftear', type => '<Tearoff>' },
	{ path => '/File/Quit', accelerator => '<control>Q', callback => \&main_window_close },
	{ path => '/_Options', type => '<Branch>' },
	{ path => '/Options/otear', type => '<Tearoff>' },
	{ path => '/Options/Hide directories in list', type => '<ToggleItem>', accelerator => '<control>D', callback => \&clist_toggle_dirs },
	{ path => '/Options/Show hidden files', type => '<ToggleItem>', accelerator => '<control>H', callback => \&toggle_hidden_files },
	{ path => '/_Tools', type => '<Branch>' },
	{ path => '/Tools/ttear', type =>'<Tearoff>' },
	{ path => '/Tools/Burn CD', accelerator => '<control>B', callback => \&burn_cd_init },
	{ path => '/Tools/Vim mode', accelerator => '<control>V', callback => \&vim_mode_init },
	{ path =>  '/_Help', type => '<LastBranch>' },
	{ path => '/Help/htear', type => '<Tearoff>' },
	{ path => '/Help/About', callback => \&show_about_box }
);
# xpm data
my @folder_xpm_data = (
	"16 16 4 1",
	"       c None s None",
	".      c black",
	"X      c #808080",
	"o      c white",
	"                ",
	"  ..            ",
	" .Xo.    ...    ",
	" .Xoo. ..oo.    ",
	" .Xooo.Xooo...  ",
	" .Xooo.oooo.X.  ",
	" .Xooo.Xooo.X.  ",
	" .Xooo.oooo.X.  ",
	" .Xooo.Xooo.X.  ",
	" .Xooo.oooo.X.  ",
	"  .Xoo.Xoo..X.  ",
	"   .Xo.o..ooX.  ",
	"    .X..XXXXX.  ",
	"    ..X.......  ",
	"     ..         ",
	"                ");
my $folder_pixmap;
my $folder_mask;

# setup gtk event loop
set_locale Gtk;
init Gtk;
create_gui ();
ctree_init ();
clist_init ();
main Gtk;

# create gui
sub create_gui
{
	# main window
	$window = new Gtk::Window ("toplevel");
	$window->set_default_size (600, 400);
	$window->set_title ("opsplorer");
	$window->signal_connect ("delete_event", \&main_window_close);
	show $window;

	# pixmaps
	my $style = $window->get_style->bg ("normal");
	($folder_pixmap, $folder_mask) = Gtk::Gdk::Pixmap ->
		create_from_xpm_d ($window->window, $style, @folder_xpm_data);
		
	# vertical box for menu/hpaned/statusbar
	my $vbox = new Gtk::VBox ($false, 0);
	$window->add ($vbox);
	
	# create menu
	my $accel_group = new Gtk::AccelGroup;
	my $item_factory = new Gtk::ItemFactory ("Gtk::MenuBar", "<main>", $accel_group);
	$item_factory->create_items (@menu_items);
	$window->add_accel_group ($accel_group);
	$menu = $item_factory->get_widget ("<main>");
	$vbox->pack_start ($menu, $false, $false, 0);
	
	# create hpaned
	$hpaned = new Gtk::HPaned;
	$hpaned->set_handle_size (10);
	$hpaned->set_gutter_size (8);
	$vbox->pack_start ($hpaned, $true, $true, 0);
	
	# create scrolled window and tree
	my $scrwin = new Gtk::ScrolledWindow ("", "");
	$scrwin->set_policy ("automatic", "always");
	$scrwin->set_usize (150, -1);
	$hpaned->add1 ($scrwin);
	$ctree = new_with_titles Gtk::CTree (1, "path", "node");
	$ctree->set_column_auto_resize (1);
	$ctree->column_titles_hide;
	$scrwin->add_with_viewport ($ctree);
	$ctree->set_selection_mode ("single");
	$ctree->drag_dest_set ("all", ["copy", "move"], @target_table[0..1]);
	$ctree->signal_connect ("drag_data_received", \&ctree_drag_received);
	$ctree->signal_connect ("drag_motion", \&ctree_drag_motion);
	$ctree->signal_connect ("tree_select_row", \&ctree_selection_made);
	$ctree->signal_connect ("tree_expand", \&ctree_expand);
	$ctree->signal_connect ("tree_collapse", \&ctree_collapse);
	
	# statusbar
	$statusbar = new Gtk::Statusbar;
	$vbox->pack_start ($statusbar, $false, $false, 0);
	
	# show all widgets
	show_all $window;
	return;
}

# close main window
sub main_window_close
{
	Gtk->exit (0);
	return 0;
}

# about box
sub show_about_box
{
}

# ctree functions
sub ctree_init
{
	my @globpattern;
	$path = "/";
	if ($show_hidden_files) { @globpattern = </.*> }
	push (@globpattern, </*>);
	$ctree->clear;
	my $root = $ctree->insert_node (undef, undef, [$path, "local root"], 0, undef, undef, undef, undef, $false, $false);
	ctree_insert_dummy ($root);
}
sub ctree_drag_received
{
	my ($widget, $context, $x, $y, $data, $info, $time) = @_;
	$drag_delete_data = "";
	my $errors = "";
	for my $entry (split (/\n/, $drag_data))
	{
		# TODO use File::Copy
		if (system ("cp -R -p -f '$entry' '$ctree_dest'"))
		{
			$errors .= "Error while copying $entry to $ctree_dest: #$?\n";
		}
		else { $drag_delete_data .= $entry."\n" }
	}
	if ($errors ne "") { draw_message_box ($errors) }
}
sub ctree_drag_motion
{
  my ($widget, $context, $x, $y, $time) = @_;
	(my $target) = $widget->get_selection_info ($x, $y);
	$ctree_dest = $ctree->node_get_text ($ctree->node_nth ($target), 0);
	$context->status ($context->suggested_action, $time);
	return 1;
}
sub ctree_selection_made
{
	my ($tree,$node) = @_;
	$path = $ctree->node_get_text ($node, 0);
	if ($vim_mode) { vim_open_file ($path) }
	else { clist_show_files () }
}
sub ctree_expand
{
	my ($tree,$node) = @_;
	my @globpattern;
	$ctree->freeze;
	my ($dummy) = $node->row->children;
	my $nodepath = $ctree->get_text ($node, 0);
	if ($ctree->get_text ($dummy, 0) eq "")
	{
		if ($show_hidden_files) { @globpattern = <$nodepath/.*> }
		push (@globpattern, <$nodepath/*>);
		for my $globentry (@globpattern)
		{
			my $entry = $globentry;
			if (-d $entry && $entry !~ '\.\.?$')
			{
				my $isleaf = $true;
				if (has_subdirs ($entry)) { $isleaf = $false }
				if ($vim_mode) { $isleaf = $false }
				my $entrytext = $entry;
				$entrytext =~ s#.*/##;
				$entry =~ s#//#/#g;
				my $node = $ctree->insert_node ($node, undef, [$entry, $entrytext], 0, undef, undef, undef, undef, $isleaf, $false);
				ctree_insert_dummy ($node) unless $isleaf;
			}
		}
		if ($vim_mode)
		{
			for my $globentry (@globpattern)
			{
				my $entry = $globentry;
				if (-f $entry)
				{
					my $isleaf = $true;
					my $entrytext = $entry;
					$entrytext =~ s#.*/##;
					$entry =~ s#//#/#g;
					my $node = $ctree->insert_node ($node, undef, [$entry, $entrytext], 0, undef, undef, undef, undef, $isleaf, $false);
				}
			}
		}
		if ($dummy) { $ctree->remove ($dummy); }
	}
	$ctree->thaw;
}
sub ctree_collapse
{
}
sub ctree_insert_dummy
{
	my ($parent) = @_;
	return $ctree->insert_node ($parent, undef, ["", ""], 0, undef, undef, undef, undef, $false, $false);
}
sub has_subdirs
{
	my ($dir) = @_;
	foreach my $entry (<$dir/*>) { return 1 if (-d $entry) }
	return 0;
}

# clist functions
sub clist_init
{
	if ($active_widget) { $active_widget->destroy }
	my $scrwin = new Gtk::ScrolledWindow ("", "");
	$scrwin->set_policy ("automatic", "automatic");
	#$scrwin->set_usize (400, 200);
	$clist = new_with_titles Gtk::CList (("Name", "Size", "Date", "Attribs"));
	$clist->set_selection_mode ("extended");
	$clist->signal_connect ("event", \&clist_event);
	$scrwin->add ($clist);
	$clist->drag_source_set (["button1_mask", "button3_mask"], ["copy", "move"], @target_table);
	$clist->signal_connect ("drag_data_get", \&clist_start_drag);
	$clist->signal_connect ("drag_data_delete", \&clist_drag_delete);
	$hpaned->add2 ($scrwin);
	$scrwin->show_all;
	$ctree->select_row (0, 0);
	$active_widget = $scrwin;
}
sub clist_show_files
{
	my @globpattern;
	if ($show_hidden_files) { @globpattern = <$path/.*>; }
	push (@globpattern, <$path/*>);

	# clean list,freeze
	$clist->clear;
	$clist->freeze;

	# get directories first
	if ($clist_show_dirs)
	{
		if ($path ne "/")
		{
			my $row = $clist->append ("..", "", "", "");
			$clist->set_pixtext ($row, 0, "..", 4, $folder_pixmap, $folder_mask);
		}
		for my $entry (@globpattern)
		{
			if (-d $entry && $entry !~ '/\.\.?$')
			{
				my ($mode, $size, $mtime) = (lstat ($entry)) [2, 7, 9];
				my ($mon, $day, $year, $hour, $min) = (localtime ($mtime)) [4, 3, 5, 2, 1];
				my $date = ($year + 1900) . "/";
				$date .= ($mon < 10 ? "0" : "") . $mon . "/";
				$date .= ($day < 10 ? "0" : "") . $day . " ";
				$date .= ($hour < 10 ? "0" : "") . $hour . ":";
				$date .= ($min < 10 ? "0" : "") . $min;
				my $attrib = $mode;
				my $clist_entry = $entry;
				$clist_entry =~ s#/.*/##g;
				my $row = $clist->append ($clist_entry, $size, $date, $attrib);
				$clist->set_pixtext ($row, 0, $clist_entry, 4, $folder_pixmap, $folder_mask);
			}
		}
	}
	# now files
	for my $entry (@globpattern)
	{
		unless(-d $entry)
		{
	    my ($mode, $size, $mtime) = (lstat ($entry)) [2, 7, 9];
	    my ($mon, $day, $year, $hour, $min) = (localtime ($mtime)) [4, 3, 5, 2, 1];
			my $date = ($year + 1900) . "/";
			$date .= ($mon < 10 ? "0" : "") . $mon . "/";
			$date .= ($day < 10 ? "0" : "") . $day . " ";
			$date .= ($hour < 10 ? "0" : "") . $hour . ":";
			$date .= ($min < 10 ? "0" : "") . $min;
			my $attrib = $mode;
			$entry =~ s#/.*/##g;
			$clist->append ($entry, $size, $date, $attrib);
		}
	}
	$clist->thaw;
	$clist->columns_autosize;
}
sub clist_toggle_dirs
{
	$clist_show_dirs = ! $clist_show_dirs;
	clist_show_files ();
}
sub clist_event
{
	my ($list, $ev) = @_;
	if ($ev->{button} == 1 and $ev->{type} eq "2button_press")
	{
		my ($row, $col) = $list->get_selection_info ($ev->{x}, $ev->{y});
		my $data = $clist->get_text ($row, 0);
		(my $pixtext) = $clist->get_pixtext ($row, 0);
		$data = $path . "/" . $data . $pixtext;
		$data =~ s#//#/#g;
		if (-d $data)
		{ 
			if ($data =~ '\.\.$')
			{
				$ctree->select ($ctree->selection->row->parent);
			}
			else
			{
				$ctree->expand ($ctree->selection);
				my $node = $ctree->selection->row->children;
				while ($ctree->get_text ($node, 0) ne $data) { $node = $node->next }
				$ctree->select ($node);
			}
		}
	}
}
sub clist_drag_delete
{
	my ($widget, $context, $data)=@_;
	for my $entry (split (/\n/, $drag_delete_data))
	{
		# TODO directory unlink
		if (! unlink ($entry))
		{
			draw_message_box ("Error while removing $entry: $!\n");
		}
	}
}
sub clist_start_drag
{
	my ($list, $context, $data, $info, $time) = @_;
	my @selected = $clist->selection;
	$drag_data = "";
	foreach my $entry (@selected)
	{
		my $text = $clist->get_text($entry, 0);
		(my $pixtext) = $clist->get_pixtext ($entry, 0);
		$drag_data = $drag_data . $path . "/" . $text . $pixtext . "\n" unless $pixtext eq "..";
	}
	$data->set ($data->target, 8, $drag_data);
}
sub toggle_hidden_files
{
	$show_hidden_files = ! $show_hidden_files;
	ctree_init ();
	clist_show_files ();
}

# burn cd
sub burn_cd_init
{
	if (! $burn_cd_vpaned)
	{
		if ($active_widget) { $active_widget->destroy }
		my $burn_cd_vpaned = new Gtk::VPaned;
		$hpaned->add2 ($burn_cd_vpaned);
		$active_widget = $burn_cd_vpaned;

		my $scrwin = new Gtk::ScrolledWindow ("", "");
		$scrwin->set_policy ("automatic", "automatic");
		#$scrwin->set_usize (400, 200);
		$clist = new_with_titles Gtk::CList (("Name", "Size", "Date", "Attribs"));
		$clist->set_selection_mode ("extended");
		$clist->signal_connect ("event", \&clist_event);
		$scrwin->add ($clist);
		$clist->drag_source_set (["button1_mask", "button3_mask"], ["copy", "move"], @target_table);
		$clist->signal_connect ("drag_data_get", \&clist_start_drag);
		$clist->signal_connect ("drag_data_delete", \&clist_drag_delete);
		$burn_cd_vpaned->add1 ($scrwin);
		$scrwin->show_all;
		$ctree->select_row (0, 0);
		
		my $burn_cd_vbox = new Gtk::VBox;
		$burn_cd_vpaned->add2 ($burn_cd_vbox);
		
		my $bbox = new Gtk::HButtonBox;
		$bbox->set_layout_default ("start");
		$bbox->set_child_size_default (20, 20);
		my $button = new Gtk::Button ("Add");
		$button->signal_connect ("clicked", \&burn_cd_add);
		$bbox->pack_start ($button, $true, $false, 0);
		$button = new Gtk::Button ("Remove");
		$button->signal_connect ("clicked", \&burn_cd_remove);
		$bbox->pack_start ($button, $true, $false, 0);
		$button = new Gtk::Button ("Burn CD");
		$bbox->pack_start ($button, $true, $false, 0);
		$button = new Gtk::Button ("Close");
		$button->signal_connect ("clicked", \&burn_cd_box_close);
		$bbox->pack_start ($button, $false, $false, 0);
		$burn_cd_vbox->pack_start ($bbox, $false, $false, 0);

		my $scrwin = new Gtk::ScrolledWindow ("", "");
		$scrwin->set_policy ("automatic", "automatic");
		$burn_cd_clist = new_with_titles Gtk::CList (("Files to burn"));
		$burn_cd_clist->set_selection_mode ("extended");
		$burn_cd_clist->drag_dest_set ("all", ["copy", "move"], @target_table[0..1]);
		$burn_cd_clist->signal_connect ("drag_data_received", \&burn_cd_clist_drag_received);
		$scrwin->add ($burn_cd_clist);
		$burn_cd_vbox->pack_start ($scrwin, $true, $true, 0);
	
		show_all $hpaned;
	}
}
sub burn_cd_clist_drag_received
{
	my ($widget, $context, $x, $y, $data, $info, $time) = @_;
	$drag_delete_data = "";
	for my $entry (split (/\n/, $drag_data))
	{
		$entry =~ s#//#/#g;
		my $row = $burn_cd_clist->append ($entry);
		if (-d $entry)
		{
			$burn_cd_clist->set_pixtext ($row, 0, $entry, 4, $folder_pixmap, $folder_mask);
		}
	}
	$burn_cd_clist->columns_autosize;
}
sub burn_cd_remove
{
	my @select = $burn_cd_clist->selection;
	# remove from bottom up, rows would change otherwise
	for my $entry (reverse sort @select)
	{
		$burn_cd_clist->remove ($entry);
	}
}
sub burn_cd_add
{
	for my $entry ($clist->selection)
	{
		my $data = $clist->get_text ($entry, 0);
		(my $pixtext) = $clist->get_pixtext ($entry, 0);
		$data = $path . "/" . $data . $pixtext;
		$data =~ s#//#/#g;
		my $row = $burn_cd_clist->append ($data);
		if (-d $data)
		{
			$burn_cd_clist->set_pixtext ($row, 0, $data, 4, $folder_pixmap, $folder_mask);
		}
	}
}
sub burn_cd_box_close
{
	$active_widget->destroy;
	$burn_cd_vpaned = 0;
	clist_init ();
	clist_show_files ();
}

# vim mode
sub vim_mode_init
{
	if ($active_widget) { $active_widget->destroy }
	my $viewport = new Gtk::Viewport (0, 0);
	$hpaned->add2 ($viewport);
	$vim_socket = new Gtk::Socket;
	$viewport->add ($vim_socket);
	$viewport->show_all;

	$vim_socket_id = $vim_socket->window->XWINDOW;
	system ("gvim -geom 70x30 --socketid $vim_socket_id");
	$active_widget = $viewport; 
	$vim_mode = $true;
}
sub vim_open_file
{
	my ($file) = @_;
	if (-f $file)
	{
		system ("gvim --socketid $vim_socket_id --remote-send '<Esc>:e $file<CR>'");
	}
}

# message box
sub draw_message_box
{
	my ($msg) = @_;
	my $dialog = new Gtk::Dialog;
	$dialog->set_default_size (400, 200);
	my $scrwin = new Gtk::ScrolledWindow;
	$scrwin->set_policy ("automatic","automatic");
	my $label = new Gtk::Label ($msg);
	$scrwin->add_with_viewport ($label);
	$dialog->vbox->pack_start ($scrwin, $true, $true, 0);
	my $button = new_with_label Gtk::Button ("OK");
	$button->signal_connect ("clicked", \&message_box_close, $dialog);
	$dialog->action_area->pack_start ($button, $true, $true, 10);
	show_all $dialog;
}
sub message_box_close
{
	my ($widget, $dialog) = @_;
	$dialog->destroy;
}


# vim:syn=perl:
